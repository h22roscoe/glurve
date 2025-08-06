import gleam/erlang/application
import gleam/http
import gluid
import lustre/attribute
import lustre/element
import lustre/element/html.{html}
import lustre/server_component
import wisp.{type Request, type Response}

pub fn handle_request(request: Request) -> Response {
  use req <- middleware(request)

  // Serve static files from the public directory.
  let assert Ok(priv_dir) = application.priv_directory("glurve")
  use <- wisp.serve_static(req, under: "/static", from: priv_dir <> "/static")

  case wisp.path_segments(req) {
    [] -> serve_html(req)
    ["lustre", "runtime.mjs"] -> serve_runtime(req)
    _ -> wisp.not_found()
  }
}

fn middleware(req: Request, handle_request: fn(Request) -> Response) -> Response {
  // Permit browsers to simulate methods other than GET and POST using the
  // `_method` query parameter.
  let req = wisp.method_override(req)

  // Log information about the request and response.
  use <- wisp.log_request(req)

  // Return a default 500 response if the request handler crashes.
  use <- wisp.rescue_crashes

  // Rewrite HEAD requests to GET requests and return an empty body.
  use req <- wisp.handle_head(req)

  // Known-header based CSRF protection for non-HEAD/GET requests
  // use req <- wisp.csrf_known_header_protection(req)

  // Handle the request!
  handle_request(req)
}

fn glurve_user_id() -> String {
  gluid.guidv4()
}

// HTML ------------------------------------------------------------------------

fn serve_html(req: Request) -> Response {
  let html =
    html([attribute.lang("en")], [
      html.head([], [
        html.meta([attribute.charset("utf-8")]),
        html.meta([
          attribute.name("viewport"),
          attribute.content("width=device-width, initial-scale=1"),
        ]),
        html.title([], "Glurve Fever"),
        html.script(
          [attribute.type_("module"), attribute.src("/lustre/runtime.mjs")],
          "",
        ),
      ]),
      html.body([], [
        server_component.element([server_component.route("/ws")], []),
      ]),
    ])
    |> element.to_document_string_tree

  case wisp.get_cookie(req, "glurve_user_id", wisp.PlainText) {
    Ok(_) -> {
      wisp.html_response(html, 200)
    }
    Error(_) -> {
      wisp.html_response(html, 200)
      |> wisp.set_cookie(
        req,
        "glurve_user_id",
        glurve_user_id(),
        wisp.PlainText,
        // 30 days
        60 * 60 * 24 * 30,
      )
    }
  }
}

// JAVASCRIPT ------------------------------------------------------------------

fn serve_runtime(req: Request) -> Response {
  use <- wisp.require_method(req, http.Get)

  let assert Ok(file_path) = application.priv_directory("lustre")
  let file_path = file_path <> "/static/lustre-server-component.min.mjs"

  wisp.ok()
  |> wisp.set_header("content-type", "application/javascript")
  |> wisp.file_download(named: file_path, from: file_path)
}
