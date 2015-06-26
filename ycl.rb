require "net/http"
require "uri"
require "json"
require "curses"
require "eventmachine"
require "em-http-request"
require "wcwidth"

class YWOTClient

  REFRESH_RATE = 3
  POLL_RATE = 0.010
  EDIT_SEND_RATE = 1

  TILE_HEIGHT = 8
  TILE_WIDTH = 16

  def initialize
    # maps [x,y] to tile JSON object as given by server
    @tiles = {}
    @url = "http://www.yourworldoftext.com/" + (ARGV[0] || "")

    @x = 0
    @y = 0
    @cx = 0
    @cy = 0

    @mode = :normal

    @csrf_cookie = nil
    @edit_queue = []

  end

  def get_tile(x, y)
    @tiles[[x,y]]
  end

  def get_tile_content(x, y)
    get_tile(x, y)["content"]
  end

  def make_request(minx, miny, maxx = minx, maxy = miny)
    params = {
      fetch: 1,
      min_tileX: minx,
      min_tileY: miny,
      max_tileX: maxx,
      max_tileY: maxy,
      v: 3
    }
    EM::HttpRequest.new(@url).get(query: params).callback do |http|
      begin
        data = JSON.parse(http.response)
        data.each do |coords, tile|
          @tiles[coords.split(",").map(&:to_i).reverse] = tile
        end
      rescue JSON::ParserError => e
        status "server sent an error"
      end
    end.errback do |http|
      raise http.error
    end

  end

  def obtain_csrf_token
    EM::HttpRequest.new("http://www.yourworldoftext.com/").get.callback do |http|
      @csrf_cookie = http.response_header["SET_COOKIE"].split(/;\s*/).first
      @csrf_token = @csrf_cookie.split("=").last
    end.errback do |http|
      raise "failed to obtain CSRF token!"
    end
  end

  def pos_to_tile(x, y)
    [x / TILE_WIDTH, y / TILE_HEIGHT]
  end

  def pos_to_loc(x, y)
    [*pos_to_tile(x, y).reverse, y % TILE_HEIGHT, x % TILE_WIDTH]
  end

  def tile_offset(x, y)
    (y % TILE_HEIGHT) * TILE_WIDTH + x % TILE_WIDTH
  end

  def tile_to_pos(tx, ty)
    [tx * TILE_WIDTH, ty * TILE_HEIGHT]
  end

  def craft_edit_raw(tile_y, tile_x, x, y, char)
    time = Time.now.to_i * 1000
    [tile_y, tile_x, x, y, time, char, "Email me before scripting"]
  end

  def craft_edit(x, y, char)
    craft_edit_raw(*pos_to_loc(x, y), char)
  end

  def get_dims
    width, height = Curses.cols, Curses.lines
    [@x - width/2, @y - height/2, @x + width/2, @y + height/2]
  end

  def draw
    width, height = Curses.cols, Curses.lines

    Curses.clear
    topx, topy, botx, boty = get_dims

    (topx..botx).each do |x|
      (topy..boty).each do |y|
        realx, realy = x - topx, y - topy
        Curses.setpos(realy, realx)
        tx, ty = pos_to_tile(x, y)
        offset = tile_offset(x, y)
        begin
          content = get_tile_content(tx, ty)
          char = content[offset]
          char = "." if char.width > 1
          Curses.addstr(char)
        rescue NoMethodError => e
          # this just means the tile wasn't found.
        end

      end
    end

    Curses.setpos(@cy, @cx)
  end

  def update_status
    status "-- #{@mode.to_s.upcase} --  |  #{pos_to_loc(@x + @cx, @y + @cy)}"
  end

  def send_edits
    EM::HttpRequest.new(@url).post(

      head: {"cookie" => @csrf_cookie, "X-CSRFToken" => @csrf_token},
      body: "edits=#{JSON.dump(@edit_queue)}"
    )

    status "sent #{@edit_queue.size} edits"

    @edit_queue = []
  end

  def display
    Curses.init_screen
    Curses.crmode
    Curses.noecho
    Curses.setpos(0, 0)
    Curses.timeout = 0
    width, height = Curses.cols, Curses.lines

    @cx = width/2
    @cy = height/2

    EM.add_periodic_timer(REFRESH_RATE) do
      topx, topy, botx, boty = get_dims
      topx_t, topy_t = pos_to_tile(topx, topy)
      botx_t, boty_t = pos_to_tile(botx, boty)
      make_request(topx_t - 1, topy_t - 1, botx_t + 1, boty_t + 1)
      draw
    end

    EM.add_periodic_timer(EDIT_SEND_RATE) do
      next if @edit_queue.size == 0
      next if !@csrf_cookie

      send_edits
    end

    EM.add_periodic_timer(POLL_RATE) do
      cmd = Curses.getch

      case @mode
      when :normal
        if cmd == "q"
          quit
        elsif DELTAS[cmd]
          move_by(*DELTAS[cmd])
        elsif cmd == "i"
          @mode = :insert
          @insert_row = @x + @cx
          draw
        elsif cmd == "e"
          eval(File.read("./script.rb"))
        end
      when :insert
        if cmd == 27
          @mode = :normal
          draw
        elsif cmd == 10
          @cx = @insert_row - @x
          move_by(0, 1)
          fix_coords
        elsif cmd == 127
          move_by(-1, 0)
          setcurchar(" ")
          draw
        elsif cmd != nil
          setcurchar(cmd)
          move_by(1, 0)
          draw
        end

      end

      update_status
      Curses.setpos(@cy, @cx)
    end

    Signal.trap("INT") { quit }
  end

  def move_by(dx, dy)
    @cx += dx
    @cy += dy
    fix_coords
  end

  def fix_coords
    width, height = Curses.cols, Curses.lines

    if @cx >= width
      @x += @cx - width + 1
      @cx = width - 1
    end
    if @cx < 0
      @x += @cx
      @cx = 0
    end
    if @cy >= height
      @y += @cy - height + 1
      @cy = height - 1
    end
    if @cy < 0
      @y += @cy
      @cy = 0
    end

    draw
  end

  # edit the character under the cursor
  def setcurchar(char)
    topx, topy, _, _ = get_dims
    setchar(topx + @cx, topy + @cy, char)
  end

  # edit the character at x, y
  def setchar(x, y, char)
    edit = craft_edit(x, y, char)
    ty, tx, y, x, _, _, _ = edit
    offset = tile_offset(x, y)
    (@tiles[[tx, ty]]["content"][offset] = char) rescue NoMethodError

    @edit_queue << edit
  end



  def quit
    Curses.close_screen
    exit
  end


  private def status(msg)
    Curses.setpos(Curses.lines - 1, 0)
    Curses.addstr(msg)
  end

  DELTAS = {
    "l" => [1, 0],
    "h" => [-1, 0],
    "j" => [0, 1],
    "k" => [0, -1],
    "L" => [TILE_WIDTH, 0],
    "H" => [-TILE_WIDTH, 0],
    "J" => [0, TILE_HEIGHT],
    "K" => [0, -TILE_HEIGHT],
  }
end

EM.run do
  cl = YWOTClient.new
  cl.obtain_csrf_token
  cl.display
end
