// Dynamic Island for Hyprland
// run with:  qs -p ~/.config/quickshell/island
import Quickshell

ShellRoot {
    Variants {
        model: Quickshell.screens
        delegate: Island {}
    }
    Variants {
        model: Quickshell.screens
        delegate: StatsIsland {}
    }
    Variants {
        model: Quickshell.screens
        delegate: ControlIsland {}
    }
}
