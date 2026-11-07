slint::slint! {
    import { LineEdit, Button } from "std-widgets.slint";
    export component AppWindow inherits Window {
        title: "Hello";
        width: 320px;
        height: 120px;
        in-out property <string> name: "World";
        in-out property <string> greeted;
        callback greet();
        callback exit();
        VerticalLayout {
            padding: 8px;
            spacing: 6px;
            HorizontalLayout {
                spacing: 6px;
                Text { text: "Name:"; vertical-alignment: center; }
                LineEdit { text <=> root.name; }
            }
            HorizontalLayout {
                spacing: 6px;
                Button { text: "Greet"; clicked => { root.greet(); } }
                Button { text: "Exit"; clicked => { root.exit(); } }
            }
            Text { text: root.greeted; }
        }
    }
}
fn main() -> Result<(), slint::PlatformError> {
    let w = AppWindow::new()?;
    let ww = w.as_weak();
    w.on_greet(move || {
        let w = ww.unwrap();
        w.set_greeted(format!("Hello, {}!", w.get_name()).into());
    });
    w.on_exit(|| { let _ = slint::quit_event_loop(); });
    w.run()
}
