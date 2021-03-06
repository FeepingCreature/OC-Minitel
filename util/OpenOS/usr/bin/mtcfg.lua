local event = require "event"
local serial = require "serialization"
local computer = require "computer"
local shell = require "shell"

local hostname = os.getenv("HOSTNAME")
local args, ops = shell.parse(...)
local cfgfile = args[1]
local cfg = {}

local function clear()
 io.write("\27[2J\27[H")
end

local function writecfg()
 local fobj = io.open(cfgfile, "wb")
 if fobj then
  fobj:write(serial.serialize(cfg))
  fobj:close()
  print("Settings successfully written!")
 end
end

if cfgfile then -- if a config file argument is specified, load it
 local fobj = io.open(cfgfile, "rb")
 if not fobj then
  print("Error: couldn't open file")
  return false
 end
 cfg = serial.unserialize(fobj:read("*a"))
 fobj:close()
 if not cfg then
  print("Error: couldn't unserialize file")
  return
 end
else -- if not, set the hostname and edit the minitel config file
 -- you could just replace this whole block with an error message I guess, but let's default to configuring minitel
 cfgfile = "/etc/minitel.cfg"
 if not hostname then
  print("Hostname not configured.")
  hostname = computer.address():sub(1,8)
  io.write("New hostname? ["..hostname.."] ")
  local nhostname = io.read()
  if nhostname:len() > 0 then
   hostname = nhostname
  end
  local fobj = io.open("/etc/hostname","wb")
  if fobj then
   fobj:write(hostname)
   fobj:close()
  end
  os.execute("hostname --update")
  print("Hostname set to "..hostname..". Press any key to continue.")
  event.pull("key_down")
 end

 cfg.debug = false -- some default settings
 cfg.port = 4096
 cfg.retry = 10
 cfg.retrycount = 64
 cfg.route = true
 cfg.rctime = 15
 cfg.pctime = 30
 cfg.sroutes = {}
 
 if ops.firstrun then -- if --firstrun, quit now
  io.write("Should this machine route packets?\nThis should be disabled on large networks.\n\nRoute packets? [Y/n]: ")
  local rp = io.read():lower():sub(1,1)
   if rp == "n" then
   cfg.route = false
  end
  os.execute("rc minitel enable")
  writecfg()
  print("Run mtcfg to configure advanced settings.")
  return false
 end
 
 local fobj = io.open(cfgfile, "rb") -- attempt to replace the default settings
 if fobj then
  cfg = serial.unserialize(fobj:read("*a")) or cfg
  fobj:close()
 end
end

local keytab = {} -- contains the keys because we don't want to work with the table indices directly
for k,v in pairs(cfg) do
 if type(v) ~= "table" then
  keytab[#keytab+1] = k
 end
end
table.sort(keytab)

local selected = 1
local run, config = true, true

local function drawmenu()
 clear()
 print("Value\tType\t\tSetting")
 for k,v in pairs(keytab) do
  if k == selected then
   io.write("\27[30;47m")
  end
  print(tostring(cfg[v]).."\t"..type(cfg[v]).."\t\t"..v.."\27[0m")
 end
 print("Use the arrow keys to navigate, space to edit a setting, q to quit, and enter to confirm.")
end

local function editsetting(k)
 if type(cfg[k]) ~= "boolean" then
  clear()
  print("Current setting for "..k..": "..tostring(cfg[k]))
 else
  cfg[k] = not cfg[k]
  return
 end
 io.write("New setting for "..k.."? ["..tostring(cfg[k]).."] ")
 local ns = io.read()
 if ns:len() > 0 then
  if type(cfg[k]) == "number" then
   ns = tonumber(ns) or cfg[k]
  end
  cfg[k] = ns
 end
end

while run do -- main loop
 drawmenu()
 local _,_, ch, co = event.pull("key_down")
 if ch == 113 and co == 16 then
  run = false
  config = false
 elseif ch == 13 and co == 28 then
  run = false
 elseif ch == 0 and co == 208 then
  selected = selected + 1
  if selected > #keytab then
   selected = #keytab
  end
 elseif ch == 0 and co == 200 then
  selected = selected - 1
  if selected < 1 then
   selected = 1
  end
 elseif ch == 32 and co == 57 then
  editsetting(keytab[selected])
 end
end

clear()

if not config then
 print("Aborted.")
 return
end

print("Writing settings...")

