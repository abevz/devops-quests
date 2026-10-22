"""Translations may change explanatory text, never executable contracts."""

import pytest
import yaml

from devops_quests.catalog import ROOT
from devops_quests.code_translation import code_tokens, same_code


@pytest.mark.parametrize(
    ("language", "original", "translated"),
    [
        (
            "hcl",
            '# Имя\nvariable "name" { description = "Имя компонента" }',
            '# Name\nvariable "name" { description = "Component name" }',
        ),
        (
            "terraform",
            'error_message = "Требуется ${var.name}, минимум 3"',
            'error_message = "Need ${var.name}, minimum 3"',
        ),
        (
            "bash",
            '# Проверка\nprintf "Готово: %s\\n" "$name"',
            '# Check\nprintf "Ready: %s\\n" "$name"',
        ),
        ("sh", "echo 'Готово'", "echo 'Ready'"),
        (
            "yaml",
            '# Проверка\nmsg: "Готово {{ name }}"',
            '# Check\nmsg: "Ready {{ name }}"',
        ),
        ("yaml", "msg: Готово\nreplicas: 2", "msg: Ready\nreplicas: 2"),
        (
            "go",
            '// Проверка\nfmt.Printf("Готово: %s\\n", name)',
            '// Check\nfmt.Printf("Ready: %s\\n", name)',
        ),
        (
            "python",
            '# Проверка\nprint("Готово", name)',
            '# Check\nprint("Ready", name)',
        ),
        (
            "json",
            '{"description":"Имя компонента","name":"worker"}',
            '{"description":"Component name","name":"worker"}',
        ),
    ],
)
def test_explanatory_text_can_be_translated(language, original, translated):
    assert code_tokens(language, original) == code_tokens(language, translated)


@pytest.mark.parametrize(
    ("language", "original", "changed"),
    [
        ("hcl", 'variable "name" {}', 'variable "title" {}'),
        ("hcl", 'source = "./modules/worker"', 'source = "./modules/other"'),
        ("hcl", 'default = "north"', 'default = "south"'),
        ("hcl", 'description = "Имя ${var.name}"', 'description = "Name ${var.title}"'),
        ("hcl", 'error_message = "Минимум 3"', 'error_message = "Minimum 4"'),
        ("bash", "kubectl get pods # список", "kubectl delete pods # list"),
        ("bash", 'echo "$name"', 'echo "$token"'),
        ("bash", 'echo "Тест $(cat /tmp/route)"', 'echo "Test $(rm /tmp/route)"'),
        (
            "bash",
            'echo "Тест $(echo $(cat /tmp/route))"',
            'echo "Test $(echo $(rm /tmp/route))"',
        ),
        ("bash", 'echo "north" > route.txt', 'echo "south" > route.txt'),
        ("bash", 'echo "north" | tee route.txt', 'echo "south" | tee route.txt'),
        ("bash", 'printf "Имя: %s\\n" "$name"', 'printf "Name: %d\\n" "$name"'),
        ("bash", 'cat "/tmp/route"', 'cat "/tmp/other"'),
        ("yaml", 'image: "example.invalid/app:1"', 'image: "example.invalid/app:2"'),
        ("yaml", 'metadata:\n  name: "worker"', 'metadata:\n  name: "other"'),
        ("yaml", 'msg: "Готово {{ name }}"', 'msg: "Ready {{ token }}"'),
        ("go", 'os.Open("/tmp/route")', 'os.Open("/tmp/other")'),
        ("python", 'open("/tmp/route")', 'open("/tmp/other")'),
        ("python", 'print(f"Готово {name}")', 'print(f"Ready {token}")'),
        (
            "json",
            '{"name":"worker","description":"Имя"}',
            '{"name":"other","description":"Name"}',
        ),
        ("json", '{"description":"Имя"}', '{/* comment */"description":"Name"}'),
        ("text", "Готово: 2", "Ready: 2"),
        ("console", "$ echo name\nимя", "$ echo name\nname"),
        ("bash", 'echo "first"\necho "second"', 'echo "first"'),
        ("hcl", "a = var.first\nb = var.second", "b = var.second\na = var.first"),
    ],
)
def test_operational_tokens_and_outputs_cannot_change(language, original, changed):
    assert code_tokens(language, original) != code_tokens(language, changed)


def test_fence_language_and_count_are_preserved():
    assert not same_code("```hcl\na=1\n```", "```bash\na=1\n```")
    assert not same_code('```bash\necho "a"\n```', "")


@pytest.mark.parametrize("wrapper", ["> ", "> > "])
@pytest.mark.parametrize("fence", ["```", "~~~~"])
def test_callout_code_uses_the_same_translation_contract(wrapper, fence):
    def block(language, text):
        return "\n".join(
            wrapper + line for line in [fence + language, *text.splitlines(), fence]
        )

    for language, source, translated in [
        (
            "text",
            "lab/\n  main.tf # главный файл\n  vars.tf # входы",
            "lab/\n  main.tf # main file\n  vars.tf # inputs",
        ),
        (
            "mermaid",
            "sequenceDiagram\n    participant A as Клиент\n    A->>A: Проверка",
            "sequenceDiagram\n    participant A as Client\n    A->>A: Check",
        ),
        (
            "yaml",
            'metadata:\n  name: worker\nmsg: "Готово"',
            'metadata:\n  name: worker\nmsg: "Ready"',
        ),
    ]:
        assert same_code(block(language, source), block(language, translated))
    assert not same_code(block("yaml", "replicas: 2"), block("yaml", "replicas: 3"))
    assert not same_code(block("text", "Готово: 2"), block("text", "Ready: 2"))
    assert not same_code(block("bash", "    echo hello"), block("bash", "  echo hello"))
    assert not same_code(
        block("bash", "echo hello"), block("bash", "echo hello").replace(wrapper, "", 1)
    )


def test_display_labels_and_file_layout_comments_are_not_commands():
    assert same_code(
        '```mermaid\nA["Первый шаг"] --> B["Следующий"]\n```',
        '```mermaid\nA["First step"] --> B["Next"]\n```',
    )
    assert not same_code(
        '```mermaid\nA["Шаг"] --> B\n```', '```mermaid\nC["Step"] --> B\n```'
    )
    source = "```text\nlab/\n  main.tf  # главный файл\n```"
    assert same_code(source, "```text\nlab/\n  main.tf  # main file\n```")
    assert not same_code(source, "```text\nlab/\n  other.tf  # main file\n```")
    assert not same_code(
        "```text\n# Первый запуск\nchanged: [localhost]\n```",
        "```text\n# First run\nchanged: [localhost]\n```",
    )


def test_module_guide_descriptions_are_english_and_contract_is_preserved():
    folder = ROOT / "docs/guides/terraform-7.1/i18n"
    original = yaml.safe_load((folder / "ru.yaml").read_text())["text"]
    english = yaml.safe_load((folder / "en.yaml").read_text())["text"]
    assert 'description = "Component name"' in english
    assert 'error_message = "name must contain at least 3 characters."' in english
    assert 'description = "Имя компонента"' not in english
    assert same_code(original, english)


def test_sequence_diagram_aliases_and_messages_preserve_actor_identity():
    source = "```mermaid\nsequenceDiagram\n    participant A as Первый запуск\n    A->>B: Получить блокировку\n```"
    translated = "```mermaid\nsequenceDiagram\n    participant A as First run\n    A->>B: Acquire lock\n```"
    assert same_code(source, translated)
    assert not same_code(source, translated.replace("A->>B", "A->>C"))


def test_structured_messages_do_not_mask_configuration_payloads():
    assert code_tokens(
        "yaml", 'apiVersion: v1\nkind: ConfigMap\ndata:\n  msg: "north"'
    ) != code_tokens("yaml", 'apiVersion: v1\nkind: ConfigMap\ndata:\n  msg: "south"')
    assert code_tokens("json", '{"data":{"description":"north"}}') != code_tokens(
        "json", '{"data":{"description":"south"}}'
    )
    assert code_tokens("yaml", "debug:\n  msg: |\n    Готово\n") == code_tokens(
        "yaml", "debug:\n  msg: |\n    Ready\n"
    )


def test_yaml_aliases_do_not_hide_shared_configuration_changes():
    original = 'description: &value "north"\ndata:\n  route: *value'
    assert code_tokens("yaml", original) != code_tokens(
        "yaml", original.replace("north", "south")
    )
    assert code_tokens("yaml", original) != code_tokens(
        "yaml", original.replace("&value", "&other")
    )


@pytest.mark.parametrize(
    "parameter", ["$?", "$#", "$@", "$*", "$$", "$!", "$-", "$0", "$12"]
)
def test_shell_special_parameters_remain_operational(parameter):
    assert code_tokens("bash", f'echo "{parameter}"') != code_tokens(
        "bash", f'echo "{parameter[1:]}"'
    )


@pytest.mark.parametrize(
    "language,source,changed",
    [
        ("go", 'fmt.Printf("%[1]s", name)', 'fmt.Printf("%[1]d", name)'),
        (
            "go",
            'fmt.Printf("%[3]*.[2]*[1]f", a, b, c)',
            'fmt.Printf("%[2]*.[3]*[1]f", a, b, c)',
        ),
        (
            "bash",
            'printf "%2$s" "$first" "$second"',
            'printf "%1$s" "$first" "$second"',
        ),
        ("python", 'print("%(user)s")', 'print("%(other)s")'),
    ],
)
def test_indexed_and_named_format_parameters_are_preserved(language, source, changed):
    assert code_tokens(language, source) != code_tokens(language, changed)


@pytest.mark.parametrize("language", ["bash", "hcl", "yaml", "go", "python", "json"])
def test_bare_command_snippets_in_explanations_remain_exact(language):
    source = {
        "bash": 'echo "Выполнить kubectl get pods"',
        "hcl": 'description = "Выполнить kubectl get pods"',
        "yaml": 'msg: "Выполнить kubectl get pods"',
        "go": 'fmt.Println("Выполнить kubectl get pods")',
        "python": 'print("Выполнить kubectl get pods")',
        "json": '{"description":"Выполнить kubectl get pods"}',
    }[language]

    def fenced(text):
        return f"```{language}\n{text}\n```"

    assert same_code(fenced(source), fenced(source.replace("Выполнить", "Run")))
    assert not same_code(
        fenced(source),
        fenced(source.replace("Выполнить", "Run").replace(" get ", " delete ")),
    )


@pytest.mark.parametrize("command", ["cat", "ls", "custom-harness"])
@pytest.mark.parametrize(
    "location", ['echo "{text}"', "# {text}", 'description = "{text}"']
)
def test_arbitrary_embedded_commands_cannot_be_rewritten(command, location):
    language = "hcl" if location.startswith("description") else "bash"
    before = location.format(text=f"Выполнить {command} config")
    translated = location.format(text=f"Run {command} config")
    assert same_code(
        f"```{language}\n{before}\n```", f"```{language}\n{translated}\n```"
    )
    assert not same_code(
        f"```{language}\n{before}\n```",
        f"```{language}\n{translated.replace(command, 'other-command')}\n```",
    )


def test_already_english_explanations_keep_their_existing_fragments():
    assert not same_code(
        '```python\nprint("Run cat /tmp/file")\n```',
        '```python\nprint("Run ls /tmp/file")\n```',
    )


@pytest.mark.parametrize("keyword", ["sep", "end"])
def test_print_configuration_arguments_cannot_be_translated(keyword):
    source = f'```python\nprint("Готово", {keyword}=" ")\n```'
    assert not same_code(source, source.replace('=" "', '=""'))
    assert same_code(source, source.replace("Готово", "Ready"))


@pytest.mark.parametrize(
    "before,after",
    [
        ("pod app-frontend-1", "pod app-other-frontend-1"),
        ("--all-namespaces", "--watch all-namespaces"),
        ("custom-harness config", "custom harness config"),
        ("option=value", "option value"),
        ("cat config && restart service", "cat config restart service"),
    ],
)
def test_embedded_identifier_flag_and_operator_boundaries_are_preserved(before, after):
    source = f'```yaml\ndebug:\n  msg: "Проверьте {before}"\n```'
    target = f'```yaml\ndebug:\n  msg: "Check {after}"\n```'
    assert not same_code(source, target)


@pytest.mark.parametrize(
    "language,source,changed",
    [
        ("go", 'fmt.Printf("%s", " ")', 'fmt.Printf("%s", "")'),
        ("go", 'fmt.Errorf("%s", " ")', 'fmt.Errorf("%s", "")'),
        ("bash", 'printf "%s" " "', 'printf "%s" ""'),
        ("python", 'print("Готово", **{"sep": " "})', 'print("Ready", **{"sep": ""})'),
        ("python", 'print(["Готово", " "])', 'print(["Готово", ""])'),
    ],
)
def test_format_data_and_nested_configuration_literals_remain_exact(
    language, source, changed
):
    assert not same_code(
        f"```{language}\n{source}\n```", f"```{language}\n{changed}\n```"
    )


@pytest.mark.parametrize("operator", ["&", ";", "2>&1"])
def test_shell_command_operators_in_comments_cannot_change(operator):
    assert not same_code(
        f"```bash\n# Запустить worker {operator}\n```",
        "```bash\n# Start worker\n```",
    )


def test_mermaid_display_markup_remains_exact():
    source = '```mermaid\nA["Первый<br/>шаг"] --> B\n```'
    translated = '```mermaid\nA["First<br/>step"] --> B\n```'
    assert same_code(source, translated)
    assert not same_code(source, translated.replace("<br/>", "<hr/>"))
    assert not same_code(source, translated.replace("<br/>", '<br class="other"/>'))
