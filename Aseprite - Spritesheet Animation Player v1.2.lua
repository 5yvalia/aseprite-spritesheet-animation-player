-- Aseprite Spritesheet Animation Player v1.2


-- REFERENCES -- 
local spritesheet -- The active document this script is locked to (set at launch)
local dlg
local timer
local click_timer
local listener

-- CONFIGURATION  --
-- (Can be modified)
    local zoom = 5 -- Default zoom level at start up. Can be changed via the UI slider or mouse scroll wheel
    local collapsed = false -- If true, the options are hidden at start up
    local frame_X, frame_Y = 0,0 -- Set default area at top-left most of the spritesheet at start up. Can be changed via set start frame button in the UI
    local frame_width, frame_height = 16,16 -- Default frame size 
    local frame_count = 3 --Default number of animation frames at start up (minimum 2). Can be changed via frame count input field in the UI
    local animation_vertical = false -- If enabled, spritesheet frames play from top to bottom. Disabled by default to play from left to right
    local animation_mirror_flip = false -- If enabled (and ping-pong is also enabled), mirrors the frame horizontally during the ping-pong reverse. Disabled by default
    local animation_fps = 8 -- Default playback speed in frames per second (1-60). Can be changed via the FPS slider
    local animation_loop = true -- Repeats animation forever until disabled. Enabled by default but can be toggled in the UI
    local animation_pingpong = false -- Repeats the animation back and forth if enabled. Disabled by default but can be toggled in the UI
    local canvas_size = 128 -- Width and height of the preview canvas in pixels

  
-- (Do not modify)
    local MIN_FRAME_COUNT = 2
    local animation_order = 1 
    local is_playing = false
    local frame_current = 0
    local pan_x, pan_y = 0, 0 
    local dragging, drag_x, drag_y = false, 0, 0
    local click_pending, click_x, click_y = false, 0, 0
    local double_click_time = 0.35

    frame_count = math.max(MIN_FRAME_COUNT, frame_count)

local OPTION_IDS = {
  "option_animation_label",
  "option_animation_loop",
  "option_animation_vertical",
  "option_animation_pingpong",
  "option_animation_mirror_flip",
  "option_frame_count_label",
  "option_frame_count",
  "option_animation_fps_label",
  "option_animation_fps",
  "option_zoom_label",
  "option_zoom",
}

-----------------------------------------------------------------------
-- FUNCTIONS: MAINTAIN DIALOG SIZE --
-----------------------------------------------------------------------
local function keep_dialog_size(fn)
  if not dlg then
    fn()
    return
  end

  local before = dlg.bounds
  fn()
  local after = dlg.bounds

  if after.x ~= before.x or after.y ~= before.y
     or after.width ~= before.width or after.height ~= before.height then
    dlg.bounds = Rectangle(before.x, before.y, before.width, before.height)
  end
end

local function sprite_is_open()
  if not spritesheet then return false end
  local ok, found = pcall(function()
    for _, s in ipairs(app.sprites) do
      if s == spritesheet then return true end
    end
    return false
  end)
  return ok and found
end

-- Filename of the active document (shortened if too long)
local MAX_FILENAME_LENGTH = 32
local function get_document_name()
  local name = "Untitled"
  if spritesheet and spritesheet.filename and spritesheet.filename ~= "" then
    name = app.fs.fileName(spritesheet.filename)
  end
  if #name > MAX_FILENAME_LENGTH then
    name = name:sub(1, MAX_FILENAME_LENGTH - 3) .. "..."
  end
  return name
end

-- Helper text showing frame size (width x height) of the selected area
local function get_frame_size_text()
  return string.format("Frame size: %d x %d", frame_width, frame_height)
end

-----------------------------------------------------------------------
-- FUNCTION: SHOW / HIDE PLAYBACK CONTROLS --
-----------------------------------------------------------------------
local function set_playing_ui(playing)
  if not dlg then return end
  keep_dialog_size(function()
    dlg:modify{ id="play", text = playing and "Stop" or "Play" }
    dlg:modify{ id="previous", visible = not playing }
    dlg:modify{ id="next", visible = not playing }
  end)
end

local function set_fps(value)
  animation_fps = math.max(1, math.min(60, math.floor(value + 0.5)))

  if timer and is_playing then
    timer:stop()
    timer.interval = 1.0 / animation_fps
    timer:start()
  end
end

-- Mirror-Flip is grayed out until Ping-Pong is enabled
local function update_mirror_flip_state()
  if not dlg then return end
  dlg:modify{ id="option_animation_mirror_flip", enabled=animation_pingpong }
end

-----------------------------------------------------------------------
-- FUNCTION: SHOW / HIDE OPTIONS-
-----------------------------------------------------------------------
local function apply_options_visibility()
  local visible = not collapsed
  for _, id in ipairs(OPTION_IDS) do
    dlg:modify{ id=id, visible=visible }
  end

  dlg:modify{
    id="collapse_toggle", 
    text = collapsed and "Show Options" or "Hide Options"
  }
end

local function toggle_options()
  collapsed = not collapsed
  keep_dialog_size(apply_options_visibility)
end
-----------------------------------------------------------------------
-- FUNCTION: SET START FRAME FROM SELECTION --
-----------------------------------------------------------------------
local function get_start_frame()
  if not sprite_is_open() then
    app.alert("The sprite this player was opened with is no longer open!")
    return
  end

  local frame_selection = spritesheet.selection
  if frame_selection.isEmpty then
    app.alert("Make a selection using the marquee tool!")
    return
  end

  local bounds = frame_selection.bounds
  frame_X, frame_Y, frame_width, frame_height = bounds.x, bounds.y, bounds.width, bounds.height
  dlg:modify{ id="frame_size_label", text=get_frame_size_text() }
  dlg:repaint()
end
-----------------------------------------------------------------------
-- FUNCTION: ANIMATION FRAME UPDATE --
-----------------------------------------------------------------------
local function stop_animation()
  local was_playing = is_playing

  if timer then timer:stop() end
  is_playing = false
  frame_current = 0
  animation_order = 1

  if was_playing then set_playing_ui(false) end
end

-- Manual stepping (prev/next buttons)
local function step_frame(step)
  frame_current = frame_current + step

  if frame_current > frame_count - 1 then
    frame_current = 0
  elseif frame_current < 0 then
    frame_current = frame_count - 1
  end
end

local function update_loop()
  frame_current = frame_current + animation_order
  if animation_pingpong then
    if frame_current >= frame_count - 1 then
      animation_order = -1
    elseif frame_current <= 0 then
      if animation_loop then
        animation_order = 1
      else
        stop_animation()
      end
    end
    return
  end

  if frame_current >= frame_count then
    if animation_loop then
      frame_current = 0
    else
      stop_animation()
    end
  elseif frame_current < 0 then
    if animation_loop then
      frame_current = frame_count - 1
    else
      stop_animation()
    end
  end
end

local function on_tick()
  -- Stop animation if the locked sprite was closed
  if not sprite_is_open() then
    stop_animation()
    return
  end

  update_loop()
  dlg:repaint()
end

local function play_animation()
  if is_playing then return end

  -- One timer is created once and reused for every Play
  if not timer then
    timer = Timer{ interval = 1.0 / animation_fps, ontick = on_tick }
  end

  animation_order = 1
  timer.interval = 1.0 / animation_fps
  timer:start()
  is_playing = true
  set_playing_ui(true)
end
-----------------------------------------------------------------------
-- DIALOG: CANVAS --
-----------------------------------------------------------------------
local function create_viewport()
  dlg = Dialog("Spritesheet Animation Player")

  click_timer = Timer{
    interval = double_click_time,
    ontick = function()
      click_pending = false
      click_timer:stop()
    end
  }

  dlg:canvas{
    id = "viewport",
    width = canvas_size,
    height = canvas_size,
    hexpand = true,
    vexpand = true,
    onpaint = function(ev)
      local gc = ev.context

      -- Stop if the locked sprite was closed
      if not sprite_is_open() then
        stop_animation()
        return
      end

      local dst_width = frame_width * zoom
      local dst_height = frame_height * zoom
      -- Centered in the canvas, shifted by the pan offset, snapped to whole pixels
      local center_x = math.floor((gc.width - dst_width) / 2 + pan_x)
      local center_y = math.floor((gc.height - dst_height) / 2 + pan_y)

      local srcRect
      if animation_vertical then
        srcRect = Rectangle(
          frame_X,
          frame_Y + frame_height * frame_current,
          frame_width,
          frame_height
        )
      else
        srcRect = Rectangle(
          frame_X + frame_width * frame_current,
          frame_Y,
          frame_width,
          frame_height
        )
      end

      local dstRect = Rectangle(center_x, center_y, dst_width, dst_height)

      if animation_mirror_flip and animation_pingpong and animation_order == -1 then
        local full_image = Image(spritesheet)
        local frame_image = Image(full_image, srcRect)
        frame_image:flip()
        gc:drawImage(frame_image, frame_image.bounds, dstRect)
      else
        gc:drawImage(Image(spritesheet), srcRect, dstRect)
      end
    end,

    onwheel = function(ev)
      zoom = math.min(50, math.max(1, zoom + ev.deltaY))
      dlg:modify{id="option_zoom", value = zoom}
      dlg:repaint()
    end,

    -- PAN: hold left mouse button and drag on the canvas
    -- RESET PAN: double-click on the canvas
    onmousedown = function(ev)
      if ev.button ~= MouseButton.LEFT then return end

      if click_pending
         and math.abs(ev.x - click_x) <= 4
         and math.abs(ev.y - click_y) <= 4 then
        -- Second click of a double-click
        click_pending = false
        click_timer:stop()
        dragging = false
        pan_x, pan_y = 0, 0
        dlg:repaint()
        return
      end

      click_pending = true
      click_x, click_y = ev.x, ev.y
      click_timer:start()

      dragging = true
      drag_x, drag_y = ev.x, ev.y
    end,

    onmousemove = function(ev)
      if dragging then
        pan_x = pan_x + (ev.x - drag_x)
        pan_y = pan_y + (ev.y - drag_y)
        drag_x, drag_y = ev.x, ev.y
        dlg:repaint()
      end
    end,

    onmouseup = function(ev)
      dragging = false
    end
  }
  -----------------------------------------------------------------------
  -- FILENAME OF THE ACTIVE DOCUMENT --
  -----------------------------------------------------------------------
  :newrow()
  :label{ id="filename_label", text=get_document_name() }
  :newrow()
  :label{ id="frame_size_label", text=get_frame_size_text() }
  -----------------------------------------------------------------------
  -- ROW 1: PLAYBACK CONTROLS --
  -----------------------------------------------------------------------
  :newrow()
  :button{
    id = "previous",
    text = "<",
    hexpand = false,
    onclick = function(ev)
      keep_dialog_size(function()
        step_frame(-1)
        dlg:repaint()
      end)
    end
  }
  :button{
    id = "play",
    text = "Play",
    onclick = function(ev)
      if is_playing then
        stop_animation()
        dlg:repaint() -- Show the reset (first) frame
      else
        play_animation()
      end
    end
  }
  :button{
    id = "next",
    text = ">",
    hexpand = false,
    onclick = function(ev)
      keep_dialog_size(function()
        step_frame(1)
        dlg:repaint()
      end)
    end
  }
  -----------------------------------------------------------------------
  -- ROW 2: SET START FRAME + HIDE OPTIONS --
  -----------------------------------------------------------------------
  :newrow()
  :button{
    id = "playback_set",
    text = "Set start frame",
    onclick = function(ev) 
      keep_dialog_size(get_start_frame)
    end
  }
  :button{
    id = "collapse_toggle",
    text = "Hide Options",
    onclick = function(ev) 
        toggle_options() 
    end
  }
  -----------------------------------------------------------------------
  -- OPTIONS --
  -----------------------------------------------------------------------
  :newrow()
  :label{id="option_animation_label", text="Animation Playback:"}
  :check{
    id="option_animation_loop",
    text="Loop",
    selected=animation_loop,
    onclick = function(ev) 
        animation_loop = dlg.data["option_animation_loop"] 
    end
  }
  :check{
    id="option_animation_vertical",
    text="Vertical",
    selected=animation_vertical,
    onclick = function(ev) 
        animation_vertical = dlg.data["option_animation_vertical"] 
    end
  }
  :check{
    id="option_animation_pingpong",
    text="Ping-Pong",
    selected=animation_pingpong,
    onclick = function(ev) 
        animation_pingpong = dlg.data["option_animation_pingpong"] 
        update_mirror_flip_state()
    end
  }
  :check{
    id="option_animation_mirror_flip",
    text="Mirror-Flip", -- Only takes effect while Ping-Pong is enabled
    selected=animation_mirror_flip,
    onclick = function(ev) 
        animation_mirror_flip = dlg.data["option_animation_mirror_flip"] 
    end
  }

  :label{id="option_frame_count_label", text="Frame Count"}
  :number{
    id="option_frame_count",
    text=tostring(frame_count),
    onchange = function(ev)
      local value = math.floor(tonumber(dlg.data["option_frame_count"]) or MIN_FRAME_COUNT)
      if value < MIN_FRAME_COUNT then
        value = MIN_FRAME_COUNT
        dlg:modify{ id="option_frame_count", text=tostring(value) }
      end
      frame_count = value

      -- Keep the current frame inside the new range
      if frame_current > frame_count - 1 then
        frame_current = frame_count - 1
      end
      dlg:repaint()
    end
  }

  :label{id="option_animation_fps_label", text="Animation Speed (FPS)"}
  :slider{
    id="option_animation_fps",
    min=1, max=60, value=animation_fps,
    onchange = function(ev)
      set_fps(dlg.data["option_animation_fps"])
    end
  }

  :label{id="option_zoom_label", text="Zoom (or use mouse scroll wheel)"}
  :slider{
    id="option_zoom",
    min=1, max=100, value=zoom,
    onchange = function(ev)
      zoom = dlg.data["option_zoom"]
      dlg:repaint()
    end
  }


  if collapsed then apply_options_visibility() end

  dlg:show{wait=false, onclose=function()
    if timer then timer:stop() end
    if click_timer then click_timer:stop() end
    if listener then app.events:off(listener) end
  end}

  if collapsed then keep_dialog_size(apply_options_visibility) end
  update_mirror_flip_state()

  -- Disable Play when the active document is closed
  listener = app.events:on('sitechange', function()
    if not sprite_is_open() then
      stop_animation()
      dlg:modify{ id="play", enabled=false }
    else
      dlg:modify{ id="play", enabled=true }
    end
    dlg:repaint()
  end)
end

-- Checks if Aseprite document is open before running script
if not app.activeSprite then
  app.alert("No file found. Open an image in Aseprite first!")
  return
end

-- Lock the Spritesheet Animation Player script to active Aseprite document
spritesheet = app.activeSprite

create_viewport()