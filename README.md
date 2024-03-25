# tui_widget

Terminal UI widget based on [illwill](https://github.com/johnnovak/illwill/tree/master])

A quick preview

![preview](./tui_widget.gif)

The widgets used to work as a standalone widget and on a combinations uses of multiple widgets navigate via `[tab]` button. 

Refers to tui_app.nim for example.

Widgets:
- input box (y)

- display panel (y)

- button (y)

- list view (y)

- table (y)

- checkbox (y)

- progressbar (y)

- label (y)

- radio button

- select

- charts (y)

Basic chart feature is supported, it has a limitation. 

  - it do not aggregate the data when display.

  - support basic x and y axis display only. (maximum x-axis and y-axis based on width and height defined.)

  - since illwill is running on text based buffer, it will be very difficult to connect the dot with line, so it's not implemented.

![chart](./chart_test.png)

### Usage

```shell
git clone https://github.com/jaar23/tui_widget.git

cd tui_widget && nimble install
```

### Doc (WIP)

Refers to tests folder for example.

- basic [example](./tests/tui_test.nim)

- chart [example](./tests/chart_test.nim)

