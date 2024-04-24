### Widgets:
- input box (y)

- display panel (y)
  
  - some text content does not work well with the default text split, you can define custom text rows split and re-cal on your own

- textarea (y)
  
  - works like a textarea in HTML

  - a naive vi mode implemented, can be enable during init of widget

- button (y)

- list view (y)

- table (y)

- checkbox (y)

- progressbar (y)

- label (y)

- gauge (y)

- charts (y), powered by [asciigraph](https://github.com/Yardanico/asciigraph/tree/master). It is an awesomeeeeeee library

  - chart have some limitation, it do not aggregate the data when display.


Widgets will be auto resize when windows size changed, however, resizing widgets would not works perfectly on all the widgets. recommended to be tested the resize effect before use.

For blocking mode, it required one user action to trigger the refresh, due to `onControl` block 

For non-blocking mode, widget will be auto resize when windows changed.


Docs work in progress..