# Third-party notices

## Mermaid diagrams

Guide pages bundle [Mermaid](https://github.com/mermaid-js/mermaid) **12.2.0**
(MIT), pinned in `package.json` and `package-lock.json`, with no CDN loading.
The bundled dependencies' versions and license texts are retained in
[`web/third-party/mermaid-NOTICES.txt`](web/third-party/mermaid-NOTICES.txt).

## Cracking the Kubernetes Interview companion code

Source: https://github.com/PacktPublishing/Cracking-the-Kubernetes-Interview

Reviewed commit: `701fb3640c5ff5f1d3775bfb936a3a1eebe28ee5`.
License verified locally and against the repository on 2026-10-21.
The companion examples inform the Kubernetes fixture patterns. The following
notice is retained for code adaptations. It does not license the book text,
questions, diagrams or prose; those are not reproduced in this project.

```text
MIT License

Copyright (c) 2024 Packt

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

Metrics Server v0.9.0 components.yaml and Gateway API v1.6.3 standard-install.yaml: kubernetes-sigs, Apache-2.0. Licenses: vendor/metrics-server-LICENSE and vendor/gateway-LICENSE. Source URLs and hashes: vendor/book-components-sources.json. Adaptations restrict resources and scope to disposable kind.

## Other bundled web libraries

- @xterm/xterm 6.0.0 and @xterm/addon-fit 0.11.0: MIT.
- markdown-it 15.0.3: MIT; highlight.js 11.12.0: BSD-3-Clause.
- intl-messageformat 12.1.4 and its FormatJS dependencies: BSD-3-Clause.
- Mermaid 12.2.0 and bundled transitive libraries: see their complete pinned notices above.

The complete versions are pinned in package-lock.json. License texts for the bundled
libraries are retained under web/third-party; generated bundle legal notices are shipped
alongside web/vendor. The Terraform syntax definer remains byte-identical to its recorded
upstream revision; the provenance note uses a neutral technical term.

Container images retain their upstream distribution/component license notices. Debian,
Docker CLI, kind/Kubernetes, Ansible Core, OpenTofu and the pinned Go-compiled diagnostic
have independent upstream licenses; the application license does not replace them.
Source URLs/digests are retained in images.lock.json, labs/images.lock.json,
tools.lock.json and the release image lock. No book text is covered by the companion MIT license.
