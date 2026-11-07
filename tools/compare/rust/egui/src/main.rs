use eframe::egui;
fn main() -> eframe::Result {
    let options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default().with_inner_size([320.0, 120.0]),
        ..Default::default()
    };
    let mut name = "World".to_owned();
    let mut greeted = String::new();
    eframe::run_ui_native("Hello", options, move |ui, _frame| {
        egui::CentralPanel::default().show(ui, |ui| {
            ui.horizontal(|ui| {
                ui.label("Name:");
                ui.text_edit_singleline(&mut name);
            });
            ui.horizontal(|ui| {
                if ui.button("Greet").clicked() { greeted = format!("Hello, {name}!"); }
                if ui.button("Exit").clicked() { ui.ctx().send_viewport_cmd(egui::ViewportCommand::Close); }
            });
            ui.label(&greeted);
        });
    })
}
