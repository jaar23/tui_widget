import tui_widget

let markdownText1 = """
## nettui

![overview](./overview.png)

A real-time terminal-based network monitoring tool built with Nim. Nettui provides comprehensive visibility into network connections, traffic statistics, and process-level network activity directly in your terminal.

**Only supported in Linux**

Features
- Real-time Network Monitoring: Live updates of network connections and statistics (1 sec interval)
- Process-Level Tracking: See which processes are using network resources
- Protocol Support: Monitor TCP, UDP, IPv4, and IPv6 connections
- Traffic Visualization: Charts for total bytes sent/received over time
- Connection Details: View connection states, RTT, queue sizes, and retransmit counts
- NAT and Conntrack Support: Monitor network address translation and connection tracking (requires appropriate permissions)
- Interactive Interface: Navigate and filter connections with keyboard controls

### Installation

**Prerequisites**

- Nim compiler (version 1.6+)
- Required Nim packages:
    - tui_widget - Terminal UI widget library
    - octolog - Logging library

Building from source

```shell
# Clone the repository
git clone https://github.com/jaar23/nettui.git
cd nettui

# Build the application
nimble build

# Run it
./nettui
```

How to navigate

- Tab to navigate between different widget
- In the network table view, type `/` to search and maintain in search view. Type `Esc` to exit the search view.


### Connection Table
Displays comprehensive information for each network connection:

|Column	|Description|
|---|---|
|PID	|Process ID|
|Process	|Process name|
|Protocol	| Network protocol (TCP/UDP)|
|Local	|Local address and port|
|Remote |	Remote address and port|
|State	|Connection state|
|Sent/Received Data | transfer rates|
|RTT	| Round-trip time|
|Queue	| Transmission/receive queue sizes|
|Retr	| Retransmission count|
|ConnState| 	Connection tracking state|
|NAT Src/NAT Dst | source/destination mappings|


| Item              | In Stock | Price |
| :---------------- | :------: | ----: |
| Python Hat        |   True   | 23.99 |
| SQL Hat           |   True   | 23.99 |
| Codecademy Tee    |  False   | 19.99 |
| Codecademy Hoodie |  False   | 42.99 |

"""

let markdownText2 = """# Features Demo

## Formatting
- **Bold text** for emphasis
- *Italic text* for style  
- `Code snippets` for technical content
- [Links](url) for references

## Quotes
> "The best way to predict the future is to invent it."
> - Alan Kay

## Headers
# H1 Header
## H2 Header  
### H3 Header
#### H4 Header
##### H5 Header
###### H6 Header

Raw text without formatting.
Multiple lines
of plain text.
"""

let rawComparisonText = """# This is raw markdown
**This should not be bold**
*This should not be italic*
`This should not be code`
> This should not be a quote
- This should not be a list item
"""

# Create markdown widgets
var md1 = newMarkdown(1, 1, 50, 12, 
                     title="Markdown Widget 1", 
                     text=markdownText1,
                     bgColor=bgBlack, 
                     fgColor=fgWhite,
                     mouseEnabled=true)

var md2 = newMarkdown(52, 1, 50, 12,
                     title="Markdown Widget 2", 
                     text=markdownText2,
                     bgColor=bgBlack, 
                     fgColor=fgWhite,
                     mouseEnabled=true)

# Create another markdown widget with custom colors
var customStyle = defaultMarkdownStyle()
customStyle.headerColor = fgYellow
customStyle.boldColor = fgRed
customStyle.italicColor = fgCyan
customStyle.codeColor = fgGreen
customStyle.codeBgColor = bgBlue
customStyle.linkColor = fgMagenta
customStyle.quoteColor = fgWhite
customStyle.quoteBgColor = bgBlue

var md3 = newMarkdown(52, 14, 50, 10,
                     title="Custom Styled Markdown",
                     text="# Custom Style\n**Red bold** and *cyan italic*\n`Green code on blue`\n> Blue quote background",
                     bgColor=bgBlack,
                     fgColor=fgWhite,
                     markdownStyle=customStyle,
                     mouseEnabled=true)

var app = newTerminalApp()

app.addWidget(md1, 0.75, 0.5)
app.addWidget(md2, 0.32, 0.5)
app.addWidget(md3, 0.35, 0.5)    

# Add some event handlers to demonstrate functionality
md1.on("preupdate") do (wg: Markdown, args: varargs[string]):
  # You can add custom logic here
  discard

md2.on(Key.Enter) do (wg: Markdown, args: varargs[string]):
  wg.text = wg.text & "\n\n**New content added!** Press M to toggle markdown mode."

app.run()