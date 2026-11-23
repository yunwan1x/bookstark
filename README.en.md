<div align="center">

**Languages / 语言： [简体中文](readme.md) | English**

# BookStark

### A home for your ideas, knowledge, and next steps.

**Self-hosted knowledge management · AI-generated tools · HTML extensions · Six themes · Go + SQLite**

Capture, organize, read, create, and share in one place.<br>
Turn an idea into a note, ask AI to build a tool, and bring your content and tools into the same workspace.

[![GitHub Stars](https://img.shields.io/github/stars/yunwan1x/bookstark?style=flat-square&color=00a9bd)](https://github.com/yunwan1x/bookstark/stargazers)
[![Release](https://img.shields.io/github/v/release/yunwan1x/bookstark?style=flat-square)](https://github.com/yunwan1x/bookstark/releases)
[![Go](https://img.shields.io/badge/Go-1.25.4-00ADD8?style=flat-square&logo=go&logoColor=white)](go.mod)
[![SQLite](https://img.shields.io/badge/SQLite-Self--hosted-003B57?style=flat-square&logo=sqlite&logoColor=white)](docs/usage-and-deployment.md)
[![License](https://img.shields.io/github/license/yunwan1x/bookstark?style=flat-square)](LICENSE)

[Quick start](#quick-start) · [Features](#features-at-a-glance) · [Bookmarks and browser extension](#bookmarks-save-fast-find-again) · [HTML tools](#html-extensions-your-tools-in-one-workspace) · [Analytics and administration](#visit-analytics-and-administration) · [Six themes](#six-themes-for-your-workspace) · [Workflow](#from-capture-to-publishing) · [Languages](#language-guide) · [Contribute](#help-build-bookstark)

**Like the idea? Give BookStark a ⭐ Star and help others discover it.**

</div>

![BookStark Glacier Cyan HUD home: overview, recent visits, personal content, and calendar](docs/screenshots/theme-hud-light.png)

> All screenshots show running interfaces. Knowledge management screenshots use isolated demo data; HTML examples were captured from public tools. Click an image to view it at full size. Screenshots currently show the Chinese interface.

## Language guide

- **Read the documentation:** [简体中文](readme.md) · **English** (this page). Use the language links at the top of either README to switch.
- **Use the application:** BookStark supports Chinese and English. On desktop, open the globe menu in the header to select a language; themes are configured separately in Personal Settings.
- **Explore supporting guides:** linked detailed guides and the standalone HTML gallery are currently primarily in Chinese. The English overview, all 45 HTML examples, deployment instructions, and screenshot captions are included below. Embedded third-party tools may offer their own language options.
- **Contribute a translation:** improvements to either language are welcome through a pull request. Keep feature descriptions, screenshots, and setup instructions aligned between versions.

## Why add BookStark to your self-hosted setup?

- **Give knowledge a home and a next step.** Capture ideas in notes, collect sources as bookmarks, organize documents into books, connect research in topics, and act through tasks.
- **Find and manage what you save.** Capture links from your browser, combine keyword, tag, site, date, and status filters, then organize the results in bulk.
- **Create in different formats.** Work with Markdown, HTML, rich documents, spreadsheets, whiteboards, mind maps, and presentations.
- **Ask AI about your own materials.** Search the current account's text content, read and summarize Markdown, and review note or task drafts before creating them.
- **Bring your tools—or ask AI to build them.** Run HTML/CSS/JavaScript pages and use AI to generate and modify tools, from creative workspaces to TV players, retro gaming, and WebRTC meetings.
- **Keep control of your data and deployment.** Go and SQLite require no separate database service. Deploy with Docker; production builds can embed frontend resources and templates.
- **Extend your workspace to development operations.** Bookmarks, files, WebDAV, and administrator-only SSH, remote file, and Docker management share one entry point.
- **Manage your site after publishing.** Visit trends, recent visits, member approval, configuration, and data migration are available in the administration interface.
- **Make it comfortable to use every day.** Six themes, Chinese and English, desktop and mobile layouts, and PWA installation.

**For anyone who wants:** a personal knowledge base, a study and research workflow, a self-hosted publishing site, or a developer workspace that keeps tools next to reference material.

## Bookmarks: save fast, find again

**Make every saved link searchable, organized, and useful again.** Browser capture, flexible queries, tags, and bulk actions form one continuous workflow.

![Bookmark workspace: titles, URLs, descriptions, and tags](docs/screenshots/bookmarks-overview.png)

### Combine filters to find a half-remembered link

| What do you remember? | How to find it |
| --- | --- |
| Part of a title, URL, or summary | **Keyword search matches saved titles, URLs, and descriptions.** |
| Several related topics | **AND / OR tag combinations:** require both Development and Go, or match any selected tag. |
| The source website | **Click a site's icon to filter bookmarks from that site**, then narrow further with keywords and tags. |
| Roughly when you saved or organized it | Filter by **creation or modification date**, using 1, 7, or 30 days or a custom date range. |
| A frequently used or unorganized link | Filter by **pinned, navigation visibility, public, or untagged** status. Untagged results become an organization queue. |
| Which filters are active | Review selected conditions, remove individual filters, or reset the query. |

For example, search for `Go`, require both Development and Go tags, click the `go.dev` site icon, or review links modified this week. **Keywords, topics, sources, dates, and status work together.**

<table>
  <tr>
    <td width="50%"><strong>Advanced search · keywords and combined tags</strong><br><img src="docs/screenshots/bookmarks-search.png" alt="Advanced search · keywords and combined tags — actual interface" width="100%"></td>
    <td width="50%"><strong>Same-site search · focus on one source</strong><br><img src="docs/screenshots/bookmarks-site.png" alt="Same-site search · focus on one source — actual interface" width="100%"></td>
  </tr>
</table>

Search covers **saved bookmark titles, URLs, and descriptions**. It does not automatically crawl or index the full text of destination pages. Adding your own short summary makes future retrieval more useful.

### Organize the results in bulk

- **Add context:** edit titles, URLs, descriptions, and tags.
- **Act on a query:** select individual entries or every result matching the current filters, including results beyond the current page.
- **Update tags and status:** add/remove tags, pin/unpin, publish/unpublish, show/hide on the navigation page, or delete.
- **Migrate existing collections:** administrators can import browser bookmark HTML, turn folder hierarchies into tags, and skip duplicate URLs within the same account.
- **Maintain a useful collection:** administrators can check for broken links and move invalid bookmarks to the trash. Frequently used links can appear on the navigation page; public bookmarks can appear in the public feed.

![Bulk bookmark management: pinning, public visibility, and navigation status](docs/screenshots/bookmarks-bulk.png)

**A useful weekly habit:** open untagged bookmarks, add descriptions and tags, pin frequent references, and make selected resources public.

### Browser extension: save good material as you browse

BookStark provides a **Linkding-compatible API** for the open-source [Linkding browser extension](https://github.com/sissbruecker/linkding-extension). Your browser and workspace use the same account's bookmark collection.

- **Save the current page:** click the extension icon or use its default `Alt + Shift + L` shortcut, then fill in the title, description, and tags.
- **Search from the address bar:** type `ld`, press Space or Tab, and enter a query to open a saved link from the suggestions.
- **Organize while saving:** use default tags and tag suggestions. Saving the same URL again updates the existing entry for that account.
- **Connect to your own instance:** authorize with a personal API Token, which you can revoke in Personal Settings.

<table>
  <tr>
    <td width="50%"><strong>Connect the extension to your BookStark</strong><br><img src="docs/screenshots/bookmarks-plugin-settings.png" alt="Connect the extension to your BookStark — actual interface" width="100%"></td>
    <td width="50%"><strong>Save with a description and tags</strong><br><img src="docs/screenshots/bookmarks-plugin-save.png" alt="Save with a description and tags — actual interface" width="100%"></td>
  </tr>
</table>

**Three steps to connect:** create a token under Personal Settings → API Token → install the [Chrome extension](https://chromewebstore.google.com/detail/linkding-extension/beakmhbijpdhipnjhnclmhgjlddhidpe) or [Firefox extension](https://addons.mozilla.org/en-US/firefox/addon/linkding-extension/) → enter your BookStark root URL and token in the extension settings, save, and confirm a successful connection.

**Visibility mapping:** the current compatibility API maps **Read later / unread** to a private bookmark. Leaving it unchecked saves the bookmark as public. The extension's Shared option does not determine visibility in BookStark. Screenshots use an isolated local demo account and a standalone extension form; saving and API queries were verified.

See the [bookmark and browser extension guide (Chinese)](docs/bookmarks-and-browser-extension.md) for configuration, compatibility limits, and search examples.

## HTML extensions: your tools in one workspace

**Store knowledge, use tools, and work with AI in the same place:** describe an idea, generate a tool, refine its interface, save it, and share it.

HTML articles and documents can host HTML, CSS, and JavaScript to run interactive pages. Calculators, dashboards, creative workspaces, TV players, retro gaming, and WebRTC meeting rooms can all become usable content within your knowledge base.

### From a prompt to your own tool

1. **Describe it:** create an HTML article or document and open AI in the editor. Explain the interface and behavior you need, or import/paste an existing tool's HTML.
2. **Generate and preview:** ask AI for HTML/CSS/JavaScript, apply it, and check the running preview. Simple browser tools need no separate project or site deployment.
3. **Refine with natural language:** provide the existing code and ask for CSV export, a mobile layout, or a reset button. Review the proposed changes before applying them.
4. **Save, organize, and share:** keep the tool beside its instructions and notes, find it by tags, and publish a share link. Return to the same HTML content for updates.

For example:

> Build a project time calculator in HTML, CSS, and JavaScript. Let me add tasks, enter durations, calculate totals, and export CSV. Make it work on phones.
>
> Add a project filter to the existing tool while preserving its data and export behavior.

This is the **editor's AI generation and revision workflow**. Configure an AI service, preview its output, and confirm before use. More complex tools still need their required resources or services and functional verification.

### Why keep tools in BookStark?

| Advantage | What it changes |
| --- | --- |
| **Tools beside knowledge** | Use a tool, record the process, organize results, and share instructions from one workspace. |
| **HTML as an extension entry point** | Add custom pages, AI-generated utilities, or embeddable web apps without changing the Go backend for each tool. |
| **Ongoing customization** | Ask AI to add features, adjust layouts, and improve interactions around your needs. |
| **Private use and public sharing** | Manage the tool, its description, tags, and share entry together. |
| **Integration as needed** | Connect writing, AI, execution, and sharing; host static assets through WebDAV and connect backend services where required. |

“Bring any tool” describes an open Web/HTML integration model. Frontend-only tools can run directly; external pages must allow embedding; tools requiring APIs, backends, or local programs need those services. Each tool controls its own internal data storage and permissions.

### Example 1: the Craft creative suite

Documents, spreadsheets, presentations, images, design, CAD, and materials show how many workflows one HTML entry point can support. These are actual integrated interfaces.

<table>
  <tr>
    <td width="50%"><strong>CADCraft · CAD workspace</strong><br><img src="docs/screenshots/extension-cadcraft.png" alt="CADCraft · CAD workspace — actual interface" width="100%"></td>
    <td width="50%"><strong>DeckCraft · Presentations</strong><br><img src="docs/screenshots/extension-deckcraft.png" alt="DeckCraft · Presentations — actual interface" width="100%"></td>
  </tr>
  <tr>
    <td width="50%"><strong>MaterialCraft · Node-based materials</strong><br><img src="docs/screenshots/extension-materialcraft.png" alt="MaterialCraft · Node-based materials — actual interface" width="100%"></td>
    <td width="50%"><strong>TextureCraft · 3D textures</strong><br><img src="docs/screenshots/extension-texturecraft.png" alt="TextureCraft · 3D textures — actual interface" width="100%"></td>
  </tr>
</table>

<details>
<summary><strong>More Craft tools: documents, spreadsheets, images, audio, video, and design</strong></summary>

<table>
  <tr><td width="50%"><strong>WordCraft · Documents</strong><br><img src="docs/screenshots/extension-wordcraft.png" alt="WordCraft · Documents — actual interface" width="100%"></td><td width="50%"><strong>GridCraft · Spreadsheets</strong><br><img src="docs/screenshots/extension-gridcraft.png" alt="GridCraft · Spreadsheets — actual interface" width="100%"></td></tr>
  <tr><td width="50%"><strong>FigCraft · Interface design</strong><br><img src="docs/screenshots/extension-figcraft.png" alt="FigCraft · Interface design — actual interface" width="100%"></td><td width="50%"><strong>PhotoCraft · Image editing</strong><br><img src="docs/screenshots/extension-photocraft.png" alt="PhotoCraft · Image editing — actual interface" width="100%"></td></tr>
  <tr><td width="50%"><strong>VectorCraft · Vector design</strong><br><img src="docs/screenshots/extension-vectorcraft.png" alt="VectorCraft · Vector design — actual interface" width="100%"></td><td width="50%"><strong>DesignCraft · Page layout</strong><br><img src="docs/screenshots/extension-designcraft.png" alt="DesignCraft · Page layout — actual interface" width="100%"></td></tr>
  <tr><td width="50%"><strong>FilmCraft · Video editing</strong><br><img src="docs/screenshots/extension-filmcraft.png" alt="FilmCraft · Video editing — actual interface" width="100%"></td><td width="50%"><strong>SoundCraft · Audio production</strong><br><img src="docs/screenshots/extension-soundcraft.png" alt="SoundCraft · Audio production — actual interface" width="100%"></td></tr>
  <tr><td width="50%"><strong>EffectCraft · Motion and visual effects</strong><br><img src="docs/screenshots/extension-effectcraft.png" alt="EffectCraft · Motion and visual effects — actual interface" width="100%"></td><td width="50%"><strong>LightCraft · Photos and RAW</strong><br><img src="docs/screenshots/extension-lightcraft.png" alt="LightCraft · Photos and RAW — actual interface" width="100%"></td></tr>
  <tr><td width="50%"><strong>PdfCraft · PDF workspace</strong><br><img src="docs/screenshots/extension-pdfcraft.png" alt="PdfCraft · PDF workspace — actual interface" width="100%"></td><td width="50%"><strong>Craft Anything · File identification (Web edition)</strong><br><img src="docs/screenshots/extension-craft.png" alt="Craft Anything · File identification (Web edition) — actual interface" width="100%"></td></tr>
</table>

</details>

**Use case:** open a design, write its documentation, organize a spreadsheet, and keep what you learned as an article. Each tool's features, dependencies, and licensing follow its own implementation.

### Example 2: TV players as shareable tools

Domestic and world TV tools provide channel browsing and playback. Bring frequently watched channels into one portal instead of maintaining a separate bookmark for each.

<table>
  <tr>
    <td width="50%"><strong>Domestic TV · CCTV-1 playback</strong><br><img src="docs/screenshots/extension-tv.png" alt="Domestic TV · CCTV-1 playback — actual interface" width="100%"></td>
    <td width="50%"><strong>World TV · US Biz TV playback</strong><br><img src="docs/screenshots/extension-world-tv.png" alt="World TV · US Biz TV playback — actual interface" width="100%"></td>
  </tr>
</table>

These screenshots show actual playback of **CCTV-1** and **Biz TV in the United States**, with advancing video playback verified before capture. Availability depends on the configured sources and network.

### Example 3: a retro arcade in an HTML article

The arcade combines browser emulation, game selection, and playback controls. It supports keyboard, controller, and touch input, plus the tool's save import/export features—an example of HTML hosting more complex WebAssembly applications.

![Retro Player: game selection and browser emulation controls](docs/screenshots/extension-arcade.png)

Emulator resources load on demand. Supply game and BIOS files you are entitled to use; they are not distributed with BookStark. See the [Retro Player integration guide](integrations/retro-player/README.md).

### Example 4: WebRTC meetings and collaboration

An HTML share entry can host room creation and joining, screen and camera sharing, and real-time annotation. Discuss a design, demonstrate a tool, or review materials on a shared collaboration canvas.

![WebRTC meeting room: room entry and collaboration controls](docs/screenshots/extension-webrtc.png)

Media permissions, signaling, and connectivity depend on your deployment. The screenshot shows the entry interface, not an active multi-party call.

### All 45 public HTML examples

As of November 22, 2026, all **45 public HTML articles** have screenshots. The Craft, TV, arcade, and meeting examples appear above; the remaining 25 are grouped below. Only titles and local images are provided, with no live instance addresses. Tools requiring files, camera/microphone permissions, or collaborators may show their entry state rather than an active session.

<details open>
<summary><strong>Office and content creation</strong></summary>

<table>
  <tr>
    <td width="50%"><strong>PDF workspace · Reading, annotations, and page organization</strong><br><img src="docs/screenshots/extension-public-181.png" alt="PDF workspace · Reading, annotations, and page organization — actual interface" width="100%"></td>
    <td width="50%"><strong>PPTist · Presentation workspace</strong><br><img src="docs/screenshots/extension-public-180.png" alt="PPTist · Presentation workspace — actual interface" width="100%"></td>
  </tr>
  <tr>
    <td width="50%"><strong>Spreadsheet editor</strong><br><img src="docs/screenshots/extension-public-177.png" alt="Spreadsheet editor — actual interface" width="100%"></td>
    <td width="50%"><strong>DOCX document editor</strong><br><img src="docs/screenshots/extension-public-173.png" alt="DOCX document editor — actual interface" width="100%"></td>
  </tr>
  <tr>
    <td width="50%"><strong>Resume layout workspace</strong><br><img src="docs/screenshots/extension-public-161.png" alt="Resume layout workspace — actual interface" width="100%"></td>
    <td width="50%"><strong>Whiteboard</strong><br><img src="docs/screenshots/extension-public-171.png" alt="Whiteboard — actual interface" width="100%"></td>
  </tr>
  <tr>
    <td width="50%"><strong>Prompt manager</strong><br><img src="docs/screenshots/extension-public-170.png" alt="Prompt manager — actual interface" width="100%"></td>
    <td width="50%"><strong>Knowledge cards</strong><br><img src="docs/screenshots/extension-public-160.png" alt="Knowledge cards — actual interface" width="100%"></td>
  </tr>
</table>

</details>

<details open>
<summary><strong>Images, photography, and audio</strong></summary>

<table>
  <tr>
    <td width="50%"><strong>Time-freeze photography studio</strong><br><img src="docs/screenshots/extension-public-162.png" alt="Time-freeze photography studio — actual interface" width="100%"></td>
    <td width="50%"><strong>Vocal effects processor</strong><br><img src="docs/screenshots/extension-public-167.png" alt="Vocal effects processor — actual interface" width="100%"></td>
  </tr>
  <tr>
    <td width="50%"><strong>Image effects factory</strong><br><img src="docs/screenshots/extension-public-152.png" alt="Image effects factory — actual interface" width="100%"></td>
    <td width="50%"><strong>Camera lab</strong><br><img src="docs/screenshots/extension-public-150.png" alt="Camera lab — actual interface" width="100%"></td>
  </tr>
  <tr>
    <td width="50%"><strong>Darkroom toolbox</strong><br><img src="docs/screenshots/extension-public-149.png" alt="Darkroom toolbox — actual interface" width="100%"></td>
    <td width="50%"><strong>Image and text steganography</strong><br><img src="docs/screenshots/extension-public-147.png" alt="Image and text steganography — actual interface" width="100%"></td>
  </tr>
</table>

</details>

<details open>
<summary><strong>Learning and investment demos</strong></summary>

<table>
  <tr>
    <td width="50%"><strong>Candlestick terminology tutor</strong><br><img src="docs/screenshots/extension-public-151.png" alt="Candlestick terminology tutor — actual interface" width="100%"></td>
    <td width="50%"><strong>Tao Te Ching · Interactive 81-chapter study map</strong><br><img src="docs/screenshots/extension-public-165.png" alt="Tao Te Ching · Interactive 81-chapter study map — actual interface" width="100%"></td>
  </tr>
  <tr>
    <td width="50%"><strong>Stock selection decision workspace</strong><br><img src="docs/screenshots/extension-public-164.png" alt="Stock selection decision workspace — actual interface" width="100%"></td>
    <td width="50%"><strong>Trading simulator</strong><br><img src="docs/screenshots/extension-public-146.png" alt="Trading simulator — actual interface" width="100%"></td>
  </tr>
  <tr>
    <td width="50%"><strong>Investment fundamentals</strong><br><img src="docs/screenshots/extension-public-145.png" alt="Investment fundamentals — actual interface" width="100%"></td>
    <td width="50%"><strong>Stock trading decision map</strong><br><img src="docs/screenshots/extension-public-144.png" alt="Stock trading decision map — actual interface" width="100%"></td>
  </tr>
  <tr>
    <td width="50%"><strong>Kelly investment simulator</strong><br><img src="docs/screenshots/extension-public-143.png" alt="Kelly investment simulator — actual interface" width="100%"></td>
  </tr>
</table>

</details>

<details open>
<summary><strong>Radio, collaboration, and utilities</strong></summary>

<table>
  <tr>
    <td width="50%"><strong>Radio</strong><br><img src="docs/screenshots/extension-public-238.png" alt="Radio — actual interface" width="100%"></td>
    <td width="50%"><strong>Bookmark Atlas · Canvas archive</strong><br><img src="docs/screenshots/extension-public-166.png" alt="Bookmark Atlas · Canvas archive — actual interface" width="100%"></td>
  </tr>
  <tr>
    <td width="50%"><strong>AirDrop-style file sharing assistant</strong><br><img src="docs/screenshots/extension-public-159.png" alt="AirDrop-style file sharing assistant — actual interface" width="100%"></td>
    <td width="50%"><strong>QR code generator</strong><br><img src="docs/screenshots/extension-public-148.png" alt="QR code generator — actual interface" width="100%"></td>
  </tr>
</table>

</details>

The [complete HTML screenshot gallery (Chinese)](docs/html-examples.md) also groups all examples in one document.

> These are integration examples, not tools, media sources, or third-party resources automatically bundled with every installation. BookStark supplies the HTML editing, execution, and sharing foundation for your own workspace.

## Visit analytics and administration

**Manage content, understand visits, and maintain your site.** Whether you run a personal library or share resources with readers, common administration tasks have a visual interface.

### See how visits change after publishing

Administrators can select **24 hours, 7 days, 30 days, or 90 days** and view visit counts, IP metrics, and PV / UV trends. Recent visits show the time, path, IP, and signed-in account or guest status, helping you inspect activity around sharing and bookmarks.

![Visit analytics: date ranges, PV / UV trends, and recent visits using demo data](docs/screenshots/admin-analytics.png)

> The chart uses isolated demo data, not production traffic. Tracking currently covers the home page `/`, public feed and share pages `/shares*`, and bookmark pages `/bookmarks*`. Trends use daily aggregates. Across multiple days, “unique IPs” sums each day's distinct IP count rather than deduplicating the entire interval. Recent visits retain the latest record for each IP/account pair; they are not a request-by-request audit log.

### Manage members, configuration, and data

| Area | Capabilities |
| --- | --- |
| **Members** | Review member and approval status, approve/reject registrations, grant/revoke administrator roles, and reset passwords. |
| **System settings** | Configure the default guest theme, login and pagination options, navigation, editors, media, email, and invitation codes. |
| **Content and services** | Manage share comments, TV channels, news sources, and AI assistant configuration. |
| **Data management** | Export the whole site or a selected user's data, optionally including uploaded images and attachments; import backups and browser bookmarks, clean broken bookmarks, and separately back up the WebDAV file database. |

![Administrator member management: roles and pending approvals using demo accounts](docs/screenshots/admin-members.png)

<table>
  <tr>
    <td width="50%"><strong>System settings · Configure your site</strong><br><img src="docs/screenshots/admin-settings.png" alt="System settings · Configure your site — actual interface" width="100%"></td>
    <td width="50%"><strong>Data management · Export, import, and migrate</strong><br><img src="docs/screenshots/admin-data.png" alt="Data management · Export, import, and migrate — actual interface" width="100%"></td>
  </tr>
</table>

**Maintain your site and take your data with you.** Member/system management and analytics require administrator access. Screenshots use a local demo environment and contain no production member data or service credentials.

## Six themes for your workspace

Choose a clean interface, glass surfaces, or a science-fiction control panel under Personal Settings → User Theme.

<table>
  <tr>
    <td width="50%"><strong>Glacier Cyan HUD · Light</strong><br><img src="docs/screenshots/theme-hud-light.png" alt="Glacier Cyan HUD · Light — actual interface" width="100%"></td>
    <td width="50%"><strong>Aviation Cyan HUD · Dark</strong><br><img src="docs/screenshots/theme-hud.png" alt="Aviation Cyan HUD · Dark — actual interface" width="100%"></td>
  </tr>
  <tr>
    <td width="50%"><strong>Glass</strong><br><img src="docs/screenshots/theme-glass.png" alt="Glass — actual interface" width="100%"></td>
    <td width="50%"><strong>NVIDIA</strong><br><img src="docs/screenshots/theme-nvidia.png" alt="NVIDIA — actual interface" width="100%"></td>
  </tr>
  <tr>
    <td width="50%"><strong>Apple</strong><br><img src="docs/screenshots/theme-apple.png" alt="Apple — actual interface" width="100%"></td>
    <td width="50%"><strong>Default</strong><br><img src="docs/screenshots/theme-light.png" alt="Default — actual interface" width="100%"></td>
  </tr>
</table>

Glacier Cyan HUD uses an icy background, dark blue text, cyan lines, and cut-corner panels. Aviation Cyan HUD pairs deep blue with instrument-style hierarchy. Glass emphasizes layered surfaces; NVIDIA uses dark surfaces and green accents; Apple uses neutral grays and blue; Default offers a familiar light workspace.

Theme preferences persist in the browser and synchronize between tabs in that browser. Administrators can set a **default theme for signed-out visitors** under System Settings → System Parameters → Appearance. An existing visitor browser preference takes priority; signed-in users are unaffected by that default.

## Features at a glance

| What you want to do | What BookStark offers |
| --- | --- |
| Capture and organize | Quick notes, articles, Markdown / HTML, tags, pinning, search, and sharing |
| Build structured knowledge | Bookshelves, books, hierarchical document trees, and reading views |
| Research a question | Topic details, linked materials, summaries, tasks, and comments |
| Turn plans into action | Tasks, subtasks, completion states, dates, and reminders |
| Save and retrieve links | Browser capture, address-bar search, title/URL/description queries, AND/OR tags, site/date/status filters, bulk actions, and navigation pages |
| Work with AI | Home assistant, text search, Markdown summaries, confirmed note/task drafts, and editor assistance |
| Create beyond articles | Rich documents, spreadsheets, whiteboards, mind maps, presentations, and local tools without sign-in |
| Extend your tool platform | HTML editing/execution, AI generation/revision, and sharing; integrate Craft, TV, arcade, WebRTC, and other web tools |
| Publish content | Public feed, articles/quick notes/books/bookmarks, share links, and comments |
| Manage files and images | Image management, local WebDAV, file upload, browsing, and management |
| Manage servers | Administrator-only SSH assets, browser terminals, credentials, remote files, and Docker management |
| Build a personal portal | News, radio, world clocks, friend links, and social QR codes |
| Maintain the site | Member management, analytics, configuration, imports/exports, and trash |

## From capture to publishing

### 1. Capture the idea

Write down ideas, study summaries, and work notes. Group them with tags and revisit them through the calendar. Expand a note into a full article when needed.

![Notes: Markdown, tags, and calendar navigation](docs/screenshots/notes.png)

<details>
<summary><strong>View the article list</strong></summary>

![Article list and tag filters](docs/screenshots/articles.png)

</details>

### 2. Structure knowledge with books and connect it through topics

Use books for lasting knowledge and topics to work through specific questions. Link notes, articles, documents, bookmarks, and tasks so sources, conclusions, and actions stay together.

![Topic workspace: questions, materials, summaries, tasks, and comments](docs/screenshots/topics.png)

<table>
  <tr>
    <td width="50%"><strong>Your knowledge bookshelf</strong><br><img src="docs/screenshots/books.png" alt="Your knowledge bookshelf — actual interface" width="100%"></td>
    <td width="50%"><strong>Document tree and editor preview</strong><br><img src="docs/screenshots/book-editor.png" alt="Document tree and editor preview — actual interface" width="100%"></td>
  </tr>
</table>

### 3. Put bookmarks and plans to work

Save valuable links with your own summaries, then turn “read later” into a task you can complete.

<table>
  <tr>
    <td width="50%"><strong>Bookmarks and tags</strong><br><img src="docs/screenshots/bookmarks.png" alt="Bookmarks and tags — actual interface" width="100%"></td>
    <td width="50%"><strong>Tasks and dates</strong><br><img src="docs/screenshots/tasks.png" alt="Tasks and dates — actual interface" width="100%"></td>
  </tr>
</table>

### 4. Bring AI alongside your materials

Open the home assistant to ask about, find, and summarize the current account's content. Ask it to draft a note or task, then **review the draft and confirm before creating the record**.

- Connect a tool-capable **OpenAI-compatible or Anthropic API**, without an additional vector database.
- Stream responses and progress; stop generation, follow source links, or restore a conversation.
- Searches are account-scoped. Body reading currently supports Markdown; password-protected content and server credentials are not provided to the assistant.
- Configure your own AI service. Requests and relevant retrieved content are sent to that provider, and usage may incur charges.

![Home AI assistant panel for searching and organizing your materials](docs/screenshots/ai-assistant.png)

The screenshot shows the real panel, with no fabricated AI response. See the [AI assistant guide (Chinese)](docs/usage-and-deployment.md#首页-ai-助手第一版) for scope and configuration.

### 5. Keep creating, then share

Open local creation tools without signing in: **Markdown, rich documents, spreadsheets, whiteboards, mind maps, and presentations**. Local drafts save automatically in the current browser and support import/export.

![Local creation tools: six editor types and draft management](docs/screenshots/creation-tools.png)

Publish selected content to the public feed for visitors to browse, search, and read.

![Public feed: articles, categories, and creation tools](docs/screenshots/public-feed.png)

Local drafts are separate from account content and do not automatically sync across devices. See the [local creation tools guide (Chinese)](docs/local-creation-tools.md).

## A full workspace on your phone

Capture ideas, review notes, and work through topics on mobile. Install the PWA to keep common entry points on your home screen.

<p align="center">
  <img src="docs/screenshots/mobile-home.png" alt="Mobile home" width="30%">
  <img src="docs/screenshots/mobile-notes.png" alt="Mobile notes" width="30%">
  <img src="docs/screenshots/mobile-topics.png" alt="Mobile topics" width="30%">
</p>

The PWA provides static caching and some offline capabilities. Sign-in, AI, and server operations require a network; not every feature works offline.

## Quick start

**Build from source and run on your own machine with Docker.** This example uses Bash, Git, and OpenSSL. Data persists in the local `data/` directory.

```bash
git clone https://github.com/yunwan1x/bookstark.git
cd bookstark

# Generate secrets once; keep this file for future upgrades.
umask 077
mkdir -p data
cat > data/bookstark.env <<EOF
PORT=8089
MODE=release
TZ=Asia/Shanghai
DB_PATH=/data/bookstark.db
WEBDAV_DB_PATH=/data/bookstark-webdav.db
JWT_SECRET=$(openssl rand -hex 32)
BOOKSTARK_ASSET_SECRET=$(openssl rand -hex 32)
ADMIN_ACCOUNT=admin
ADMIN_PASSWORD=$(openssl rand -hex 16)
EOF

# Build and start
DOCKER_BUILDKIT=1 docker build -t bookstark:local .
docker run -d --name bookstark --restart unless-stopped \
  -p 127.0.0.1:8089:8089 \
  --env-file data/bookstark.env \
  -w /data -v "$(pwd)/data:/data" \
  bookstark:local

# Read the initial administrator password
sed -n 's/^ADMIN_PASSWORD=//p' data/bookstark.env
```

Open **http://localhost:8089** and sign in as `admin` with the generated password. For remote access, configure an HTTPS reverse proxy with WebSocket and SSE support.

Desktop and Android users can download GUI clients from [GitHub Releases](https://github.com/yunwan1x/bookstark/releases) and choose a local workspace or a remote server. First-time local setup lets you choose the admin password and copy it from the completion screen. Releases no longer include standalone server binaries; use Docker images for server deployments. See the [deployment and maintenance guide (Chinese)](docs/usage-and-deployment.md) for Docker Compose, GHCR images, environment variables, local development, upgrades, and backups. Use its BookStark Compose example; development proxy tools live separately under `tools/dev-proxy/`.

> Back up databases, uploads, and secrets before upgrading. Do not commit the generated environment file or regenerate it on upgrade. Changing initialization variables does not reset an existing account's password.

## Technology and openness

| Layer | Technology |
| --- | --- |
| Backend | Go + Gin + Go HTML Templates |
| Data | SQLite, with no separate database service |
| Interface | JavaScript, Tailwind CSS, CSS variables, and shared components |
| Distribution | Docker, embedded static resources/templates, and release workflows |
| Integrations | API Tokens, WebDAV, OpenAI-compatible / Anthropic AI APIs |
| License | Apache License 2.0; third-party components retain their respective licenses |

[Deployment (Chinese)](docs/usage-and-deployment.md) · [Creation tools (Chinese)](docs/local-creation-tools.md) · [News sources (Chinese)](docs/news-feeds.md) · [Repository layout (Chinese)](docs/repository-layout.md) · [Testing](tests/README.md) · [Development conventions](CLAUDE.md) · [Helper scripts](scripts/README.md)

## Help build BookStark

If BookStark fits your workflow, **give it a ⭐ Star**. It is an easy way to bookmark the project and help other self-hosting and knowledge management enthusiasts find it.

- **Try it and report feedback:** include your use case, reproduction steps, and screenshots in [Issues](https://github.com/yunwan1x/bookstark/issues).
- **Share your workspace:** show your theme, knowledge organization, or self-hosting experience.
- **Contribute:** documentation, translations, features, and fixes are welcome. Discuss larger changes in an issue first.

### Star history

<a href="https://www.star-history.com/#yunwan1x/bookstark&Date">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=yunwan1x/bookstark&amp;type=Date&amp;theme=dark">
    <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=yunwan1x/bookstark&amp;type=Date">
    <img alt="BookStark GitHub star history" src="https://api.star-history.com/svg?repos=yunwan1x/bookstark&amp;type=Date" width="100%">
  </picture>
</a>

Chart provided by [Star History](https://github.com/star-history/star-history). Loading depends on its service and cache; click the image for the interactive chart.

---

<div align="center">

**Let every note become the starting point for your next creation.**<br>
[⭐ Star BookStark](https://github.com/yunwan1x/bookstark) · [Download releases](https://github.com/yunwan1x/bookstark/releases) · [Report an issue](https://github.com/yunwan1x/bookstark/issues)

</div>
