### TODO: 

[x] hide widget

[ ] documentation

[ ] examples

[ ] error handling
    
    Ideas :thinking
    
    - centralized message channel for error message, display on terminal app statusbar

    - widget in error will be update as error state and render error

[ ] event handling
    
    References from js for inspiration

    ```javascript
    // 1.
    const btn = document.querySelector("button");

    function greet(event) {
      console.log("greet:", event);
    }

    btn.onclick = greet;

    // 2.
    const btn = document.querySelector("button");

    function greet(event) {
      console.log("greet:", event);
    }

    btn.addEventListener("click", greet);

    // 3.
    const controller = new AbortController();

    btn.addEventListener("click",
      (event) => {
        console.log("greet:", event);
      },
      { signal: controller.signal },
    ); // pass an AbortSignal to this handler

    ```
    
    EnterEvent in input, textarea (vi mode), listview, table, button as primary event trigger.

    Standardize SpaceEvent in input, textarea (vi mode), listview, table, button, eg, <leader>+<key>, for secondary trigger

    QuestionEvent in all for help text, except input, and allow user to defined their own help text.
    
    Register command event in input, textarea widget

[ ] Menu widget
