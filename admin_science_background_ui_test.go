package main

import (
	"os"
	"strings"
	"testing"
)

func TestScienceBackgroundIsGlobalAndProfileControlled(t *testing.T) {
	profile, err := os.ReadFile("templates/profile.html")
	if err != nil {
		t.Fatalf("ReadFile(profile.html) error = %v", err)
	}
	profileText := string(profile)
	for _, required := range []string{
		`id="science-background-toggle"`,
		`profile.field.background_animation`,
		`window.BookStarkBackground.set(enabled)`,
		`window.BookStarkBackground.syncControl('science-background-toggle')`,
	} {
		if !strings.Contains(profileText, required) {
			t.Fatalf("profile background toggle missing %q", required)
		}
	}

	js, err := os.ReadFile("static/js/theme.js")
	if err != nil {
		t.Fatalf("ReadFile(theme.js) error = %v", err)
	}
	jsText := string(js)
	for _, required := range []string{
		`BACKGROUND_STORAGE_KEY = 'bookstark-science-background'`,
		`window.BookStarkBackground`,
		`data-science-background`,
		`bookstark-science-bg`,
		`stored !== '0'`,
		`MATHJAX_SCRIPT = '/static/js/mathjax/tex-svg.js'`,
		`renderScienceFormula`,
		`MathJax.tex2svgPromise`,
		`script.id = script.id || 'mathjax-js'`,
		`script.addEventListener('load'`,
		`\\left\\{\\begin{array}{l}`,
		`\\nabla \\cdot \\mathbf{E}`,
		`\\nabla \\cdot \\mathbf{B}=0`,
		`\\nabla \\times \\mathbf{E}=-\\partial \\mathbf{B}/\\partial t`,
		`\\partial \\mathcal{L}/\\partial W^{(l)}`,
		`\\delta^{(l)}`,
		`\\mathrm{Attention}(Q,K,V)`,
		`\\mathrm{MultiHead}(Q,K,V)`,
		`e^{i\\pi}+1=0`,
		`\\zeta(s)=\\sum_{n=1}^{\\infty}n^{-s}`,
		`0<\\operatorname{Re}(s)<1\\ \\Longrightarrow\\ \\operatorname{Re}(s)=1/2`,
		`(i\\gamma^\\mu\\partial_\\mu-m)\\psi=0`,
		`H^2=8\\pi G\\rho/3-kc^2/a^2+\\Lambda c^2/3`,
		`S_{\\mathrm{BH}}=k_{\\mathrm{B}}c^3A/(4G\\hbar)`,
		`\\rho(\\partial_t\\mathbf{u}+\\mathbf{u}\\cdot\\nabla\\mathbf{u})`,
		`F(\\omega)=\\int_{-\\infty}^{\\infty}f(t)e^{-i\\omega t}\\,dt`,
		`H(X)=-\\sum_x p(x)\\log p(x)`,
		`\\dot{x}=\\sigma(y-x)`,
		`\\dot{y}=x(\\rho-z)-y`,
		`\\dot{z}=xy-\\beta z`,
		`E=mc^2`,
		`\\lambda=h/p`,
		`D_\\mu F^{\\mu\\nu}=J^\\nu`,
		`v=H_0d`,
		`T_{\\mathrm{H}}=\\hbar c^3/(8\\pi GMk_{\\mathrm{B}})`,
		`Z=\\sum_i e^{-E_i/(k_{\\mathrm{B}}T)}`,
		`v=V_{\\max}[S]/(K_m+[S])`,
		`\\dot{x}=\\alpha x-\\beta xy`,
		`\\dot{y}=\\delta xy-\\gamma y`,
		`x_{n+1}=rx_n(1-x_n)`,
		`\\oint_{\\partial \\Omega}`,
		`\\begin{bmatrix}`,
		`\\cos\\theta&-\\sin\\theta`,
		`(ad-bc)^{-1}\\begin{bmatrix}d&-b\\\\ -c&a\\end{bmatrix}`,
		`\\lambda\\begin{bmatrix}v_1\\\\ v_2\\end{bmatrix}`,
		`\\begin{bmatrix}\\sigma_1&0\\\\ 0&\\sigma_2\\end{bmatrix}`,
	} {
		if !strings.Contains(jsText, required) {
			t.Fatalf("global background runtime missing %q", required)
		}
	}
	if strings.Contains(jsText, `\\frac`) {
		t.Fatalf("science background formulas should avoid MathJax fraction rules that render as stray horizontal lines")
	}
	formulaStart := strings.Index(jsText, "var SCIENCE_FORMULAS = [")
	if formulaStart < 0 {
		t.Fatal("science background formula pool is missing")
	}
	formulaEnd := strings.Index(jsText[formulaStart:], "\n    ];")
	if formulaEnd < 0 {
		t.Fatal("science background formula pool is not terminated")
	}
	formulaBlock := jsText[formulaStart : formulaStart+formulaEnd]
	if got := strings.Count(formulaBlock, "{ tex:"); got != 42 {
		t.Fatalf("science background formula pool contains %d formulas, want 42", got)
	}

	css, err := os.ReadFile("static/css/variables.css")
	if err != nil {
		t.Fatalf("ReadFile(variables.css) error = %v", err)
	}
	cssText := string(css)
	for _, required := range []string{
		`.bookstark-science-bg { position: fixed; inset: 0;`,
		`[data-science-background="on"] .bookstark-science-bg`,
		`[data-science-background="on"] body > header`,
		`[data-science-background="on"] body > main`,
		`[data-science-background="on"] body > .editor-shell`,
		`[data-science-background="on"] body > .share-view-shell`,
		`.bookstark-science-formula`,
		`--science-formula-drift-x`,
		`--science-formula-rise`,
		`.bookstark-science-formula mjx-container`,
		`.bookstark-science-hud`,
		`[data-science-background="on"] .topics-page`,
		`[data-science-background="on"] .topic-rail`,
		`[data-science-background="on"] .topic-list`,
		`[data-science-background="on"] .topic-detail`,
		`[data-science-background="on"] .topic-detail-content`,
		`[data-science-background="on"] .topic-detail-body`,
		`[data-science-background="on"] .label-right`,
		`@media (prefers-reduced-motion: reduce)`,
	} {
		if !strings.Contains(cssText, required) {
			t.Fatalf("global background styles missing %q", required)
		}
	}
	for _, forbidden := range []string{
		`[data-science-background="on"] body > *:not(.bookstark-science-bg)`,
	} {
		if strings.Contains(cssText, forbidden) {
			t.Fatalf("global background styles should not override every body child, found %q", forbidden)
		}
	}

	admin, err := os.ReadFile("templates/admin_system.html")
	if err != nil {
		t.Fatalf("ReadFile(admin_system.html) error = %v", err)
	}
	adminText := string(admin)
	for _, forbidden := range []string{
		`admin-science-bg`,
		`admin-science-formula`,
		`admin-science-hud`,
	} {
		if strings.Contains(adminText, forbidden) {
			t.Fatalf("admin system should not render fixed background animation, found %q", forbidden)
		}
	}
}

func TestArticleCreateModalOutranksScienceBackground(t *testing.T) {
	tpl, err := os.ReadFile("templates/notes.html")
	if err != nil {
		t.Fatalf("ReadFile(notes.html) error = %v", err)
	}
	tplText := string(tpl)
	for _, required := range []string{
		`id="articleSettingOverlay"`,
		`openArticleSettingModal(null)`,
		`notesApp.createArticle()`,
	} {
		if !strings.Contains(tplText, required) {
			t.Fatalf("article modal template missing %q", required)
		}
	}

	notesCSS, err := os.ReadFile("static/css/notes.css")
	if err != nil {
		t.Fatalf("ReadFile(notes.css) error = %v", err)
	}
	notesText := string(notesCSS)
	for _, required := range []string{
		`.editor-overlay { display: none; position: fixed; inset: 0; z-index: 100;`,
		`.editor-overlay.active { display: flex;`,
	} {
		if !strings.Contains(notesText, required) {
			t.Fatalf("article modal overlay style missing %q", required)
		}
	}

	globalCSS, err := os.ReadFile("static/css/variables.css")
	if err != nil {
		t.Fatalf("ReadFile(variables.css) error = %v", err)
	}
	globalText := string(globalCSS)
	if !strings.Contains(globalText, `.bookstark-science-bg { position: fixed; inset: 0; display: none; overflow: hidden; pointer-events: none; z-index: 0;`) {
		t.Fatalf("science background should remain below modal overlays")
	}
	if strings.Contains(globalText, `[data-science-background="on"] body > *:not(.bookstark-science-bg)`) {
		t.Fatalf("science background should not restyle every body child")
	}
}

func TestScienceBackgroundFunctionGraphLayer(t *testing.T) {
	js, err := os.ReadFile("static/js/theme.js")
	if err != nil {
		t.Fatalf("ReadFile(theme.js) error = %v", err)
	}
	jsText := string(js)
	for _, required := range []string{
		`SCIENCE_FUNCTION_SHAPES`,
		`SCIENCE_FUNCTION_FLOATERS`,
		`SCIENCE_PATH_DISTRIBUTION`,
		`SCIENCE_PATH_EDGE_MARGIN`,
		`SCIENCE_PATH_SAMPLE_STEPS`,
		`SCIENCE_PATH_TRAVEL_MODES`,
		`SCIENCE_FORMULA_CYCLE_MS`,
		`var SCIENCE_FORMULA_CYCLE_MS = 144000;`,
		`SCIENCE_FORMULA_DESKTOP_LANES`,
		`SCIENCE_FORMULA_MOBILE_LANES`,
		`createScienceCandidatePath`,
		`createScienceEdgeToEdgePath`,
		`createScienceFormulaLanePath`,
		`scoreSciencePathVisibility`,
		`document.elementFromPoint`,
		`applyScienceFormulaPath`,
		`layoutScienceFormulas`,
		`bookstark-function-canvas`,
		`drawScienceFunctionGraphs`,
		`startScienceFunctionGraphs`,
		`stopScienceFunctionGraphs`,
		`requestAnimationFrame`,
		`cancelAnimationFrame`,
		`prefers-reduced-motion: reduce`,
		`butterfly`,
		`rose`,
		`lissajous`,
		`lorenz`,
		`scale: 0.018`,
		`scale: 0.028`,
		`scale: 0.032`,
		`scale: 0.0022`,
		`slice(0, 6)`,
		`slice(0, 3)`,
		`progress = ((timestamp + floater.delay) % floater.duration) / floater.duration`,
		`getSciencePathPoint(instance.path, progress, index)`,
		`path.endX - path.startX`,
		`path.endY - path.startY`,
		`path.startEdge`,
		`path.endEdge`,
		`formulaCount`,
		`path.duration = SCIENCE_FORMULA_CYCLE_MS`,
		`formulaLane`,
		`formulaLaneRow`,
		`formulaRows`,
		`formulaPhase`,
		`path.delay = -formulaPhase * SCIENCE_FORMULA_CYCLE_MS`,
		`bg.dataset.layoutWidth`,
		`bg.dataset.layoutHeight`,
		`layoutScienceFormulas(bg, true)`,
		`alpha = Math.sin(progress * Math.PI)`,
	} {
		if !strings.Contains(jsText, required) {
			t.Fatalf("science background function graph runtime missing %q", required)
		}
	}
	for _, forbidden := range []string{
		`heart`,
		`scale: 0.18`,
		`scale: 0.2`,
		`scale: 0.22`,
	} {
		if strings.Contains(jsText, forbidden) {
			t.Fatalf("science background function graphs should be small floating curves, found %q", forbidden)
		}
	}
	if !strings.Contains(jsText, `stopScienceFunctionGraphs();`) {
		t.Fatalf("science function graphs should stop when background is disabled")
	}

	css, err := os.ReadFile("static/css/variables.css")
	if err != nil {
		t.Fatalf("ReadFile(variables.css) error = %v", err)
	}
	cssText := string(css)
	for _, required := range []string{
		`--science-curve-primary`,
		`--science-curve-secondary`,
		`.bookstark-function-canvas`,
		`opacity: 0.72;`,
		".bookstark-function-canvas {\n  position: absolute;\n  inset: 0;\n  z-index: 1;",
		".bookstark-science-formula {\n  position: absolute;\n  z-index: 2;",
		".bookstark-science-hud {\n  position: absolute;\n  z-index: 2;",
		".bookstark-science-scan {\n  position: absolute;\n  z-index: 2;",
		`[data-theme="dark"] .bookstark-science-bg`,
		`[data-theme-style="scholar-paper"] .bookstark-science-bg`,
		`[data-theme-style="linear-saas"] .bookstark-science-bg`,
		`[data-theme-style="apple-minimal"] .bookstark-science-bg`,
		`50% { transform: translate3d(var(--science-formula-drift-x), var(--science-formula-drift-y), 0); opacity: 0.9; }`,
		`28% { transform: translate3d(var(--science-formula-drift-x), var(--science-formula-drift-y), 0); opacity: 0.82; }`,
	} {
		if !strings.Contains(cssText, required) {
			t.Fatalf("science background function graph styles missing %q", required)
		}
	}
	for _, forbidden := range []string{
		`.bookstark-science-formula:nth-child(27)`,
		`.bookstark-science-formula:nth-child(4) { left:`,
		`translateY = 24 - progress * 124`,
		`startX: width * 0.5`,
		`path.startX + path.driftX * eased`,
		`.bookstark-science-formula:nth-child(n+8) { display: none; }`,
		`return index % 2 === 0 ? 'left' : 'right'`,
		`path.delay = -(index / formulaCount) * SCIENCE_FORMULA_CYCLE_MS`,
		`[data-theme-style="ink-wash"] .bookstark-science-bg`,
		`[data-theme-style="cinnabar-seal"] .bookstark-science-bg`,
	} {
		if strings.Contains(cssText, forbidden) || strings.Contains(jsText, forbidden) {
			t.Fatalf("science background should no longer use fixed full-screen formula/curve positions, found %q", forbidden)
		}
	}
}
