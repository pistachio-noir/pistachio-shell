//! `psc completions zsh|bash|fish`: tab completion for psc's own commands.
use clap::CommandFactory;

pub fn script(shell: clap_complete::Shell) -> String {
    let mut out = Vec::new();
    clap_complete::generate(shell, &mut crate::cli::Cli::command(), "psc", &mut out);
    String::from_utf8_lossy(&out).into_owned()
}

#[cfg(test)]
mod tests {
    #[test]
    fn completions_zsh() {
        let text = super::script(clap_complete::Shell::Zsh);
        assert!(text.contains("status") && text.contains("doctor") && text.contains("force-restart"), "{text}");
    }
}
