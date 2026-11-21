//! hello-ship: a tiny CLI that shows how shipcrate fits into a real program.
//! The only shipcrate-specific lines are marked "shipcrate".

// shipcrate: the update code that `shipcrate init` put in updater/ (copy it to src/update.rs in your own project).
#[path = "../updater/update.rs"]
mod update;

const VERSION: &str = env!("CARGO_PKG_VERSION");

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match args.first().map(String::as_str) {
        Some("--version") | Some("-V") => println!("hello-ship {VERSION}"),
        // shipcrate: `hello-ship upgrade` and `hello-ship upgrade --rollback`
        Some("upgrade") => match update::upgrade(VERSION, args.iter().any(|a| a == "--rollback")) {
            Ok(msg) => println!("{msg}"),
            Err(e) => {
                eprintln!("upgrade: {e}");
                std::process::exit(1);
            }
        },
        Some("help") | Some("--help") | Some("-h") => {
            println!("hello-ship {VERSION}\n\n  hello-ship [NAME]           say hello\n  hello-ship upgrade          install the newest release (verified)\n  hello-ship upgrade --rollback   go back to the previous version\n  hello-ship --version")
        }
        name => {
            println!("👋 Hello, {}! (hello-ship {VERSION})", name.unwrap_or("world"));
            // shipcrate: after an interactive command, show the update notice / announcement (once a day, at most).
            update::notify(VERSION);
        }
    }
}
