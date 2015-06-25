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

  def initialize
    # maps [x,y] to tile JSON object as given by server
    @tiles = {}
    @url = "http://www.yourworldoftext.com/"

    @x = 0
    @y = 0
    @cx = 0
    @cy = 0

    @mode = :normal

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
      data = JSON.parse(http.response)
      data.each do |coords, tile|
        @tiles[coords.split(",").map(&:to_i).reverse] = tile
      end
    end.errback do |http|
      raise http.error
    end

  end

  def pos_to_tile(x, y)
    [x / 16, y / 8]
  end

  def tile_offset(x, y)
    (y % 8) * 16 + x % 16
  end

  def tile_to_pos(tx, ty)
    [tx * 16, ty * 8]
  end

  def display
    Curses.init_screen
    Curses.crmode
    Curses.noecho
    Curses.setpos(0, 0)
    Curses.timeout = 0
    width = Curses.cols
    height = Curses.lines

    get_dims = lambda { 
      [@x - width/2, @y - height/2, @x + width/2, @y + height/2]
    }

    @cx = width/2
    @cy = height/2

    draw = proc do
      Curses.clear
      topx, topy, botx, boty = get_dims.call

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

      status "-- #{@mode.to_s.upcase} --"

      Curses.setpos(@cy, @cx)
    end

    EM.add_periodic_timer(REFRESH_RATE) do
      topx, topy, botx, boty = get_dims.call
      topx_t, topy_t = pos_to_tile(topx, topy)
      botx_t, boty_t = pos_to_tile(botx, boty)
      make_request(topx_t - 1, topy_t - 1, botx_t + 1, boty_t + 1)
      draw.call
    end

    EM.add_periodic_timer(POLL_RATE) do
      cmd = Curses.getch

      case @mode
      when :normal
        if cmd == "q"
          quit
        elsif DELTAS[cmd]
          dx, dy = DELTAS[cmd]
          @cx += dx
          @cy += dy
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
        elsif cmd == "i"
          @mode = :insert
        end
      when :insert
        if cmd == 27
          @mode = :normal
        end

      end

      if cmd
        draw.call
      end
    end

    Signal.trap("INT") { quit }
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
    "L" => [16, 0],
    "H" => [-16, 0],
    "J" => [0, 8],
    "K" => [0, -8],
  }
end

EM.run do
  cl = YWOTClient.new
  cl.display
end
