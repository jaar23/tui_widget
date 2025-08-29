import tui_widget
import illwill

# Create dropdown options
let opts = @[
  newDropdownOption("Option 1", "opt1"),
  newDropdownOption("Option 2", "opt2"), 
  newDropdownOption("Option 3", "opt3"),
  newDropdownOption("Hidden Option", "hidden", visible = false)
]

# Create dropdown widget
let dropdown = newDropdown(10, 5, 30, 3, 
                          placeholder = "Choose an option...",
                          options = opts,
                          maxVisibleOptions = 4)

# Create label to display selected value
let selectedLabel = newLabel(10, 10, 40, 3, 
                            id = "selectedLabel",
                            text = "No selection made",
                            border = true,
                            align = Left)

# Handle selection events - update the label when selection changes
dropdown.onSelect = proc(dd: Dropdown, args: varargs[string]) =
  let value = if args.len > 0: args[0] else: ""
  let text = if args.len > 1: args[1] else: ""
  selectedLabel.text = "Selected: " & text & " (Value: " & value & ")"

# Create terminal application
var app = newTerminalApp(title="Dropdown Widget Test")

# Add widgets to the application
app.addWidget(dropdown, 0.4, 3)
app.addWidget(selectedLabel, 0.5, 3)

# Display initial values for debugging
echo "Initial selected value: ", dropdown.selectedValue()
echo "Initial selected text: ", dropdown.selectedText()

# Run the application
app.run()