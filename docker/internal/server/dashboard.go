package server

import (
	"html/template"
	"log/slog"
	"net/http"
	"net/url"
	"slices"
	"strings"

	"github.com/rubycdp/ferrum/docker/internal/browser"
)

var dashboardTemplate = template.Must(template.New("dashboard").Parse(`<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="refresh" content="3">
<title>Ferrum driver</title>
<style>
  :root { color-scheme: light dark; font-family: system-ui, sans-serif; }
  body { margin: 2rem auto; max-width: 60rem; padding: 0 1rem; }
  section { border: 1px solid #8884; border-radius: 6px; margin: 1rem 0; padding: 0.5rem 1rem; }
  h2 { font-size: 0.9rem; font-family: ui-monospace, monospace; }
  li { margin: 0.5rem 0; overflow-wrap: anywhere; }
  small { opacity: 0.7; }
</style>
</head>
<body>
<h1>Ferrum driver</h1>
{{- if .}}
<p>{{len .}} running {{if eq (len .) 1}}session{{else}}sessions{{end}}</p>
{{- range .}}
<section id="{{.ID}}">
<h2>{{.ID}}</h2>
{{- if .Pages}}
<ul>
{{- range .Pages}}
<li><a href="{{.DevTools}}" target="_blank">{{if .Title}}{{.Title}}{{else}}{{.URL}}{{end}}</a><br><small>{{.URL}}</small></li>
{{- end}}
</ul>
{{- else}}
<p><small>No pages</small></p>
{{- end}}
</section>
{{- end}}
{{- else}}
<p>No running sessions.</p>
{{- end}}
</body>
</html>
`))

type dashboardSession struct {
	ID    string
	Pages []dashboardPage
}

type dashboardPage struct {
	Title    string
	URL      string
	DevTools string
}

func (s *Server) root(w http.ResponseWriter, r *http.Request) {
	if isUpgrade(r) {
		s.connect(w, r)
		return
	}

	browsers := s.sessions.Browsers()
	slices.SortFunc(browsers, func(a, b *browser.Browser) int { return strings.Compare(a.ID, b.ID) })

	sessions := make([]dashboardSession, 0, len(browsers))
	for _, b := range browsers {
		targets, err := s.targets(b)
		if err != nil {
			slog.Warn("cannot list browser targets", "id", b.ID, "error", err)
			continue
		}

		session := dashboardSession{ID: b.ID}
		for _, target := range targets {
			if target["type"] != "page" {
				continue
			}

			id, _ := target["id"].(string)
			title, _ := target["title"].(string)
			url, _ := target["url"].(string)
			session.Pages = append(session.Pages, dashboardPage{Title: title, URL: url, DevTools: s.inspectorURL(r, id)})
		}
		sessions = append(sessions, session)
	}

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	dashboardTemplate.Execute(w, sessions)
}

func (s *Server) inspectorURL(r *http.Request, id string) string {
	ws, _ := url.Parse(s.publicURL(r, "/devtools/page/"+id, ""))
	return s.httpURL(r, "/devtools/inspector.html") + "?" + ws.Scheme + "=" + ws.Host + ws.Path
}

func (s *Server) httpURL(r *http.Request, path string) string {
	u, _ := url.Parse(s.publicURL(r, path, ""))
	u.Scheme = strings.Replace(u.Scheme, "ws", "http", 1)
	return u.String()
}
