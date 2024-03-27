# tui_widget

Terminal UI widget based on [illwill](https://github.com/johnnovak/illwill/tree/master)

These widget is <b>under development</b>, things might change or break!

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

- gauge (y)

- charts (y)

After checkout on [asciigraph](https://github.com/Yardanico/asciigraph/tree/master), switch to implement chart with this library instead. It is an awesomeeeeeee library! 

Now it support basic chart feature better, although it still has some limitation. 

  - it do not aggregate the data when display.
  

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

- gauge [example](./tests/gauge_test.nim)



