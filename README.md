## Your World of Text client

### Install dependencies
```
$ gem install wcwidth eventmachine em-http-request
```

### Run it
Start it with `ruby ycl.rb`.

Initially it will take a few seconds to fetch the screen.

## Controls

Control is modal, inspired by vi. There is normal mode and insert mode.

### Normal mode
`hjklHJKL` to move (capitals are for longer jumps)

`q` to quit

`i` to enter insert mode

### Insert mode
`<Esc>` to return to normal mode

`<Enter>` to return cursor to the column where insert mode began and move 
one row down

`<Backspace>` to backspace

Any other key inserts a character.

TODO: Arrow keys to move in insert mode
