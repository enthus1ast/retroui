use iced::widget::{button, column, row, text, text_input};
use iced::{Element, Size, Task};
struct App { name: String, greeted: String }
#[derive(Debug, Clone)]
enum Msg { Name(String), Greet, Exit }
impl App {
    fn update(&mut self, m: Msg) -> Task<Msg> {
        match m {
            Msg::Name(s) => self.name = s,
            Msg::Greet => self.greeted = format!("Hello, {}!", self.name),
            Msg::Exit => return iced::exit(),
        }
        Task::none()
    }
    fn view(&self) -> Element<'_, Msg> {
        column![
            row![text("Name:"), text_input("", &self.name).on_input(Msg::Name)].spacing(6),
            row![button("Greet").on_press(Msg::Greet), button("Exit").on_press(Msg::Exit)].spacing(6),
            text(&self.greeted)
        ].spacing(6).padding(8).into()
    }
}
fn main() -> iced::Result {
    iced::application(|| App { name: "World".into(), greeted: String::new() }, App::update, App::view)
        .title("Hello")
        .window_size(Size::new(320.0, 120.0))
        .run()
}
