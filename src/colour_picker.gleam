import gleam/list
import gleam/set
import lustre/attribute
import lustre/element
import lustre/element/html
import lustre/event
import player/colour

pub fn colour_picker(
  open: Bool,
  on_click on_click: fn(colour.Colour) -> msg,
) -> element.Element(msg) {
  html.details(
    [
      attribute.class("color-picker"),
      attribute.attribute("aria-haspopup", "listbox"),
      case open {
        True -> attribute.attribute("open", "")
        False -> attribute.none()
      },
    ],
    [
      html.summary([attribute.attribute("aria-label", "Choose colour")], []),
      html.div(
        [
          attribute.class("popover"),
          attribute.attribute("role", "listbox"),
          attribute.attribute("aria-label", "Colour choices"),
        ],
        [
          html.div(
            [attribute.class("picker-swatch-grid")],
            colour.all()
              |> set.to_list()
              |> list.map(fn(colour) { colour_swatch(colour, on_click(colour)) }),
          ),
        ],
      ),
    ],
  )
}

fn colour_swatch(colour: colour.Colour, on_click: msg) -> element.Element(msg) {
  html.div([attribute.class("picker-swatch")], [
    html.button(
      [
        attribute.attribute("type", "button"),
        attribute.attribute("aria-label", colour.to_string(colour)),
        event.on_click(on_click),
      ],
      [
        html.svg(
          [
            attribute.class("square"),
            attribute.attribute("viewBox", "0 0 100 100"),
            attribute.attribute("aria-hidden", "true"),
            attribute.attribute("height", "24px"),
            attribute.attribute("width", "24px"),
          ],
          [
            colour.to_svg_head(colour, 20.0, 10.0, 20.0, 90.0, 90.0, 50.0),
          ],
        ),
        html.span([], [html.text(colour.to_string(colour))]),
      ],
    ),
  ])
}
