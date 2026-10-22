"""Loopback HTTP API and authenticated WebSocket-to-container PTY bridge."""

import asyncio
import contextlib
import sqlite3
import time
from urllib.parse import quote, urlsplit

from aiohttp import web

from .catalog import TRACKS
from .scoring import POLICY
from .terminal import TerminalHub

COOKIE = "devops_quests_session"


def make_app(
    store,
    catalog,
    engine,
    base="/",
    hosts=("127.0.0.1", "localhost"),
    public_origin=None,
    labs=None,
):
    base = "/" + base.strip("/") + "/" if base.strip("/") else "/"
    prefix = base.rstrip("/")

    if public_origin:
        public = urlsplit(public_origin)
        if (
            public.scheme not in {"http", "https"}
            or public.hostname not in hosts
            or public.path
            or public.query
            or public.fragment
            or public.username
            or public.password
        ):
            raise ValueError("Public origin must be an exact allowed HTTP(S) origin")

    def origin_allowed(request):
        expected = public_origin or request.scheme + "://" + request.host
        return request.headers.get("Origin") == expected

    @web.middleware
    async def security(request, handler):
        if request.url.host not in hosts:
            raise web.HTTPForbidden(text="Unknown host")
        try:
            public = request.path in {
                prefix + "/",
                prefix + "/interview",
                prefix + "/profile",
                prefix + "/guides",
                prefix + "/labs",
                prefix + "/api/login",
                prefix + "/api/locales",
            } or request.path.startswith(prefix + "/assets/")
            token = request.cookies.get(COOKIE)
            session = await asyncio.to_thread(store.session, token)
            request["session"] = session
            if not public and not session:
                raise web.HTTPUnauthorized(text="Please sign in.")
            if request.method not in {"GET", "HEAD", "OPTIONS"}:
                if not origin_allowed(request):
                    raise web.HTTPForbidden(text="Origin rejected.")
                if (
                    session
                    and request.path != prefix + "/api/login"
                    and request.headers.get("X-CSRF-Token") != session["csrf"]
                ):
                    raise web.HTTPForbidden(text="CSRF token rejected.")
                if session:
                    await asyncio.to_thread(store.session, token, touch=True)
            response = await handler(request)
        except (ValueError, KeyError, PermissionError) as error:
            response = web.json_response(
                {
                    "error": {
                        "key": str(error)
                        if str(error) in catalog.resources.ui["en"]
                        else "error.request"
                    }
                },
                status=403 if isinstance(error, PermissionError) else 400,
            )
        except sqlite3.IntegrityError:
            response = web.json_response(
                {"error": {"key": "error.user_exists"}}, status=400
            )
        except web.HTTPException as error:
            if 300 <= error.status < 400:
                response = web.Response(status=error.status, headers=error.headers)
            else:
                codes = {
                    401: "error.unauthorized",
                    403: "error.origin",
                    404: "error.not_found",
                    400: "error.request",
                    429: "error.rate_limit",
                }
                response = web.json_response(
                    {"error": {"key": codes.get(error.status, "error.request")}},
                    status=error.status,
                )
        except Exception:
            import logging

            logging.getLogger(__name__).exception("Request failed")
            response = web.json_response(
                {"error": {"key": "error.operation"}},
                status=500,
            )
        response.headers.update(
            {
                "X-Content-Type-Options": "nosniff",
                "Referrer-Policy": "no-referrer",
                "Cache-Control": "no-store",
                "X-Frame-Options": "DENY",
                "Content-Security-Policy": "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; connect-src 'self'; img-src 'self' data:; object-src 'none'; base-uri 'self'; frame-ancestors 'none'",
            }
        )
        return response

    app = web.Application(middlewares=[security], client_max_size=16 * 1024)
    app["base"] = base
    terminals = TerminalHub(store, engine)
    app.on_shutdown.append(terminals.shutdown)
    hint_requests = {}

    def limit_hints(request):
        user = request["session"]["user_id"]
        now = time.monotonic()
        start, count = hint_requests.get(user, (now, 0))
        if now - start >= 60:
            start, count = now, 0
        if count >= 30:
            raise web.HTTPTooManyRequests()
        hint_requests[user] = (start, count + 1)

    async def index(request):
        return web.FileResponse(catalog.root / "web" / "index.html")

    async def asset(request):
        name = request.match_info["name"]
        # Restrict static content; quest setup/check/reference files are never served.
        allowed = {
            "app.js",
            "styles.css",
            "terminal.js",
            "controls.mjs",
            "play.mjs",
            "reference.mjs",
            "locale.mjs",
            "score-preview.mjs",
            "diagrams.mjs",
            "vendor/terminal.js",
            "vendor/markdown.js",
            "vendor/mermaid.js",
            "vendor/locale.js",
            "vendor/xterm.css",
        }
        if name not in allowed:
            raise web.HTTPNotFound()
        return web.FileResponse(catalog.root / "web" / name)

    def guide_payload(name):
        if name not in catalog.guides:
            raise web.HTTPNotFound()
        wiki = {}
        for alias, section in catalog.guides.items():
            path = section["source"].removesuffix(".md")
            for source in (path, path.rsplit("/", 1)[-1]):
                wiki[source + "#" + section["heading"]] = (
                    prefix + "/guide/" + quote(alias, safe="")
                )
        return {**catalog.guide(name), "wiki": wiki}

    async def guide(request):
        name = request.match_info["name"]
        if name not in catalog.guides:
            raise web.HTTPNotFound()
        raise web.HTTPFound(prefix + "/guides#guide=" + quote(name, safe=""))

    async def guide_content(request):
        return web.json_response(guide_payload(request.match_info["name"]))

    async def login(request):
        data = await request.json()
        token = await asyncio.to_thread(
            store.login,
            str(data.get("name", ""))[:64],
            str(data.get("password", "")),
            request.remote or "local",
        )
        if not token:
            return web.json_response({"error": {"key": "error.login"}}, status=401)
        response = web.json_response({"ok": True})
        response.set_cookie(
            COOKIE,
            token,
            httponly=True,
            samesite="Strict",
            path=base,
            max_age=24 * 3600,
            secure=public_origin.startswith("https://")
            if public_origin
            else request.secure,
        )
        return response

    async def logout(request):
        store.logout(request.cookies.get(COOKIE))
        response = web.json_response({"ok": True})
        response.del_cookie(COOKIE, path=base)
        return response

    async def state(request):
        user = request["session"]
        progress = store.progress(user["user_id"])
        campaign = store.completions(user["user_id"], "campaign")
        opened = catalog.opened(campaign)
        levels = [
            dict(
                level,
                implemented=level["id"] in catalog.quests,
                opened=level["id"] in opened,
            )
            for level in catalog.public_levels()
        ]
        run = store.run(user=user["user_id"])
        result = {
            "user": {"name": user["name"], "admin": bool(user["admin"])},
            "csrf": user["csrf"],
            "levels": levels,
            "progress": progress,
            "exams": store.exams(user["user_id"]),
            "history": store.history(user["user_id"]),
            "run": run,
            "labs": store.labs(user["user_id"]) if labs else [],
            "base": base,
            "preferences": store.preferences(user["user_id"]),
            "scoring": POLICY,
            "campaign_completed": sorted(campaign),
            "attempted_levels": store.attempted(user["user_id"]),
            "track_opened": {
                track: sorted(
                    catalog.opened(
                        campaign | store.completions(user["user_id"], "track:" + track),
                        track,
                    )
                )
                for track in TRACKS
            },
        }
        if run:
            if run["status"] == "passed":
                run["score_details"] = store.score_details(run)
            run["preparing"] = run["id"] in engine.preparing
            result["quest"] = catalog.public(
                run["level"],
                run["hints"],
                run["status"] == "passed",
                run["mode"] == "exam",
            )
        return web.json_response(result)

    async def interview(request):
        completed = {
            row["level"] for row in store.progress(request["session"]["user_id"])
        }
        return web.json_response(catalog.interview(completed))

    async def lab_index(request):
        if not labs:
            raise ValueError("error.lab_unavailable")
        return web.json_response(
            {
                "profiles": labs.catalog.public(),
                "saved": store.labs(request["session"]["user_id"]),
            }
        )

    async def lab_create(request):
        if not labs:
            raise ValueError("error.lab_unavailable")
        data = await request.json()
        if not isinstance(data, dict):
            raise web.HTTPBadRequest()
        return web.json_response(
            await labs.create(request["session"]["user_id"], data.get("profile"))
        )

    async def lab_action(request):
        if not labs:
            raise ValueError("error.lab_unavailable")
        data = await request.json()
        if not isinstance(data, dict):
            raise web.HTTPBadRequest()
        return web.json_response(
            await labs.action(
                request["session"]["user_id"],
                request.match_info["identifier"],
                data.get("action"),
                data.get("confirmation"),
            )
        )

    async def lab_terminal(request):
        if not labs or not origin_allowed(request):
            raise web.HTTPForbidden()
        from .labs import LabTerminalStore, ScopedLabTerminalEngine

        lab = labs.get(request["session"]["user_id"], request.match_info["identifier"])
        if lab["status"] != "running":
            raise ValueError("error.lab_inactive")
        return await terminals.serve(
            request,
            lab,
            request.cookies.get(COOKIE),
            store=LabTerminalStore(store),
            engine=ScopedLabTerminalEngine(labs.factory(lab)),
        )

    async def locales(request):
        return web.json_response(
            {"languages": catalog.resources.languages, "messages": catalog.resources.ui}
        )

    async def preferences(request):
        data = await request.json()
        values = catalog.resources.preferences(
            data.get("primary"), data.get("translation")
        )
        return web.json_response(
            store.set_preferences(
                request["session"]["user_id"], values["primary"], values["translation"]
            )
        )

    def active(request):
        user = request["session"]
        run = store.run(user=user["user_id"])
        if not run or run["status"] != "active":
            raise ValueError("error.start")
        if run["id"] in engine.preparing:
            raise ValueError("error.preparing")
        return run

    async def start(request):
        data = await request.json()
        result = await engine.start(
            request["session"]["user_id"],
            data.get("level"),
            data.get("mode", "normal"),
            data.get("minutes", 15),
            track=data.get("track"),
        )
        return web.json_response(result)

    async def briefing(request):
        number = int(request.match_info["number"])
        result = catalog.briefing(number)
        user = request["session"]["user_id"]
        completed = number in store.completed_any(user)
        count = (
            len(catalog.quests[number]["hints"])
            if completed
            else store.briefing_hint_count(user, number)
        )
        result["hints"] = catalog.public(number, count)["hints"]
        result["hint_access"] = {
            "completed": completed,
            "count": count,
            "total": min(len(catalog.quests[number]["hints"]), POLICY["hint_limit"]),
        }
        result["best"] = next(
            (row for row in store.progress(user) if row["level"] == number), None
        )
        return web.json_response(result)

    async def briefing_hint(request):
        number = int(request.match_info["number"])
        catalog.briefing(number)
        limit_hints(request)
        data = await request.json()
        store.reveal_briefing_hint(
            request["session"]["user_id"],
            number,
            len(catalog.quests[number]["hints"]),
            data.get("confirmed") is True,
        )
        return await briefing(request)

    async def guides(request):
        return web.json_response({"groups": catalog.guide_index()})

    async def stop(request):
        return web.json_response(await engine.stop(request["session"]["user_id"]))

    async def check(request):
        run = active(request)
        store.update(run, activity=store.clock())
        return web.json_response(await engine.poll(run, final=True))

    async def reset(request):
        return web.json_response(await engine.reset(active(request)))

    async def hint(request):
        limit_hints(request)
        return web.json_response(engine.hint(active(request)))

    async def topology(request):
        run = store.run(user=request["session"]["user_id"])
        if not run or run["status"] != "active" or run["id"] in engine.preparing:
            return web.json_response({"nodes": []})
        nodes = await asyncio.to_thread(engine.runtime.topology, run)
        return web.json_response({"nodes": nodes})

    async def add_user(request):
        data = await request.json()
        await asyncio.to_thread(
            store.add_user,
            data.get("name", ""),
            data.get("password", ""),
            request["session"],
        )
        return web.json_response({"ok": True})

    async def users(request):
        rows = await asyncio.to_thread(store.users, request["session"])
        return web.json_response({"users": rows})

    async def password(request):
        data = await request.json()
        if "user_id" in data and data["user_id"] != request["session"]["user_id"]:
            raise PermissionError("error.admin")
        await asyncio.to_thread(
            store.change_password,
            request["session"],
            request.cookies.get(COOKIE),
            data.get("current"),
            data.get("password"),
            data.get("confirmation"),
        )
        return web.json_response({"ok": True})

    def target(data):
        value = data.get("user_id")
        if not isinstance(value, int) or isinstance(value, bool) or value < 1:
            raise ValueError("error.request")
        return value

    async def reset_password(request):
        data = await request.json()
        await asyncio.to_thread(
            store.reset_password, request["session"], target(data), data.get("password")
        )
        return web.json_response({"ok": True})

    async def enabled(request):
        data = await request.json()
        user_id = target(data)
        await asyncio.to_thread(
            store.set_enabled, request["session"], user_id, data.get("enabled")
        )
        if data.get("enabled") is False:
            await engine.stop(user_id)
            if labs:
                await labs.stop_user(user_id)
        return web.json_response({"ok": True})

    async def terminal(request):
        if not origin_allowed(request):
            raise web.HTTPForbidden(text="Origin rejected.")
        run = await asyncio.to_thread(active, request)
        return await terminals.serve(request, run, request.cookies.get(COOKIE))

    app.router.add_get(prefix + "/", index)
    app.router.add_get(prefix + "/assets/{name:.*}", asset)
    app.router.add_get(prefix + "/guide/{name}", guide)
    app.router.add_get(prefix + "/api/guide/{name}", guide_content)
    app.router.add_get(prefix + "/interview", index)
    app.router.add_get(prefix + "/profile", index)
    app.router.add_get(prefix + "/guides", index)
    app.router.add_get(prefix + "/labs", index)
    app.router.add_get(prefix + "/api/labs", lab_index)
    app.router.add_post(prefix + "/api/labs", lab_create)
    app.router.add_post(prefix + "/api/labs/{identifier:[a-f0-9]{24}}", lab_action)
    app.router.add_get(
        prefix + "/api/labs/{identifier:[a-f0-9]{24}}/terminal", lab_terminal
    )
    app.router.add_get(prefix + "/api/briefing/{number:\\d+}", briefing)
    app.router.add_post(prefix + "/api/briefing/{number:\\d+}/hint", briefing_hint)
    app.router.add_get(prefix + "/api/locales", locales)
    for path, method, handler in [
        ("login", "POST", login),
        ("logout", "POST", logout),
        ("state", "GET", state),
        ("interview", "GET", interview),
        ("guides", "GET", guides),
        ("start", "POST", start),
        ("stop", "POST", stop),
        ("check", "POST", check),
        ("reset", "POST", reset),
        ("hint", "POST", hint),
        ("topology", "GET", topology),
        ("users", "POST", add_user),
        ("users", "GET", users),
        ("users/reset", "POST", reset_password),
        ("users/enabled", "POST", enabled),
        ("password", "POST", password),
        ("preferences", "POST", preferences),
        ("terminal", "GET", terminal),
    ]:
        app.router.add_route(method, prefix + "/api/" + path, handler)

    async def context(_):
        if labs:
            await labs.recover()
        task = asyncio.create_task(engine.background())
        yield
        task.cancel()
        with contextlib.suppress(asyncio.CancelledError):
            await task
        for run in store.active():
            await asyncio.to_thread(engine.runtime.teardown, run)
            store.update(run, status="interrupted", ended=store.clock())
        if labs:
            await labs.shutdown()

    app.cleanup_ctx.append(context)
    return app
