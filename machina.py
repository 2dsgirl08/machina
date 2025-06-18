import logging
import threading
import asyncio
import websockets
import shutil
import json
import os
import io
import sys
import time

if sys.platform == "win32":
    import msvcrt
else:
    import termios
    import tty

from flask import Flask
from rich.console import Console
from rich.console import Group
from rich.text import Text
from rich.style import Style
from rich.color import Color
from rich.table import Table
from rich.live import Live
from rich.panel import Panel

CONFIG = {}
WORLDS = ["natura", "lucernia", "luna_refuge", "aesteria", "caverna", "tutorial"]

with open("config.json", "r") as f:
    CONFIG = json.loads(f.read())

# ------------------------------------------------
# Classes
# ------------------------------------------------

class User:
    def __init__(self, socket, name):
        self.socket = socket
        self.name = name
        self.lastHeartbeat = time.time()
        self.queue = asyncio.Queue()
        self.log = asyncio.Queue()
        self.loop = asyncio.get_event_loop()
        
        connected_users[name] = self        
        asyncio.create_task(self.checkHeartbeat())

    async def invoke(self, data, timeout=10):
        try:
            await self.socket.send(json.dumps(data))
        except Exception as e:
            self.destroy()
            return None

        try:
            response = await asyncio.wait_for(self.queue.get(), timeout=timeout)
            return response
        except:
            return None
    
    async def send(self, data):
        try:
            await self.socket.send(json.dumps(data))
        except Exception as e:
            self.destroy()
            return None
        
    def invoke_threadsafe(self, data, timeout=10):
        future = asyncio.run_coroutine_threadsafe(self.invoke(data), self.loop)
        return future.result(timeout=timeout)
    
    def heartbeat(self):
        self.lastHeartbeat = time.time()
    
    def destroy(self):
        if not self.name in connected_users:
            return
        
        if connected_users[self.name] != self:
            return
        
        global chosenClient
        
        if chosenClient == self:
            chosenClient = None
            
        del connected_users[self.name]
        
    async def checkHeartbeat(self):
        while self.name in connected_users:
            if time.time() - self.lastHeartbeat > 15:
                self.destroy()
            
            await asyncio.sleep(1)

# ------------------------------------------------
# Webserver Handler
# ------------------------------------------------

log = logging.getLogger('werkzeug')
log.setLevel(logging.ERROR)

app = Flask(__name__)

def directory_to_dict(path):
    result = {
        "type": "directory",
        "name": os.path.basename(path),
        "children": {}
    }

    try:
        for entry in os.listdir(path):
            full_path = os.path.join(path, entry)
            if os.path.isdir(full_path):
                result["children"][entry] = directory_to_dict(full_path)
            else:
                try:
                    with open(full_path, "r", encoding="utf-8", errors="replace") as file:
                        contents = file.read()
                except Exception as e:
                    contents = f"<Error reading file: {str(e)}>"

                result["children"][entry] = {
                    "type": "file",
                    "name": entry,
                    "contents": contents
                }
    except PermissionError:
        result["error"] = "Permission denied"

    return result

@app.route("/", methods=["GET"])
def get_files():
    with open("config.json", "r") as f:
        CONFIG = json.loads(f.read())
    
    return {
        "path": directory_to_dict("client")["children"],
        "config": CONFIG
    }

def flaskMain():
    app.run(debug=False, port=CONFIG["WEBSERVER_PORT"])

# ------------------------------------------------
# Socket Handler
# ------------------------------------------------

preservedTasks = {}

async def socketHandler(websocket):
    global chosenClient
    
    user = None
    username = None

    try:
        async for message in websocket:
            data = None
            
            try:
                data = json.loads(message)
            except:
                continue

            if data['packet'] == 'identify':
                username = data['username']
                
                if username in connected_users:
                    connected_users[username].destroy()
                
                user = User(websocket, username)
                await user.send({"packet": "identified"})
                
                if username in preservedTasks:
                    await user.send({"packet": "preserveTasks", "data": preservedTasks[username]})
                    del preservedTasks[username]
                    chosenClient = user

                continue
            
            if data['packet'] == "preserveTasks":
                preservedTasks[username] = data['data']
                continue
            
            if data['packet'] == "heartbeat":
                user.heartbeat()
                continue

            await user.queue.put(data)
    except websockets.exceptions.ConnectionClosed:
        if username in connected_users:
            user.destroy()

async def socketMain():
    async with websockets.serve(socketHandler, "localhost", CONFIG["WEBSOCKET_PORT"]):
        await asyncio.Future()

# ------------------------------------------------
# Console Handler
# ------------------------------------------------

signature = """
                          __    _            
    ____ ___  ____ ______/ /_  (_)___  ____ _
   / __ `__ \/ __ `/ ___/ __ \/ / __ \/ __ `/
  / / / / / / /_/ / /__/ / / / / / / / /_/ / 
 /_/ /_/ /_/\__,_/\___/_/ /_/_/_/ /_/\__,_/  
"""

quote = "in memory of 2dsgirl08 - the best rex macro engine"
lineDivider = "────────────────────────────────────────────────────────────────────────────────────────"

connected_users = {}
chosenClient: User = None

def windows_keypress_listener(queue, loop):
    global currentInput
    global entered
    global listening
    
    while True:
        if not listening:
            continue
        
        if msvcrt.kbhit():
            ch = msvcrt.getch()
            try:
                key = ch.decode()
            except UnicodeDecodeError:
                continue

            if key.isdigit():
                currentInput += key
            elif key == '\x08':
                currentInput = currentInput[:-1]
            elif key == '\r':
                entered = True
            else:
                pass

def unix_keypress_listener(queue, loop):
    global currentInput
    global entered
    global listening
    
    fd = sys.stdin.fileno()
    old_settings = termios.tcgetattr(fd)
    try:
        tty.setcbreak(fd)
        while True:
            if not listening:
                continue
            
            ch = sys.stdin.read(1)
            if ch.isdigit():
                currentInput += ch
            elif ch == '\x7f':
                currentInput = currentInput[:-1]
            elif ch == '\n':
                entered = True
            else:
                pass
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old_settings)

def gradient_text(text: str, color_stops, width: int = None, style: str = "") -> Text:
    lines = text.splitlines()
    term_width = width or shutil.get_terminal_size((80, 20)).columns

    color_stops = sorted(color_stops, key=lambda x: x[0])
    parsed_stops = [(pos, Color.parse(color).triplet) for pos, color in color_stops]

    def interpolate_color(c1, c2, t: float) -> str:
        interp = tuple(int(c1c + (c2c - c1c) * t) for c1c, c2c in zip(c1, c2))
        return f"#{interp[0]:02x}{interp[1]:02x}{interp[2]:02x}"

    def get_color_for_t(t: float) -> str:
        for i in range(len(parsed_stops) - 1):
            pos1, col1 = parsed_stops[i]
            pos2, col2 = parsed_stops[i + 1]
            if pos1 <= t <= pos2:
                local_t = (t - pos1) / (pos2 - pos1)
                return interpolate_color(col1, col2, local_t)
        return f"#{parsed_stops[-1][1][0]:02x}{parsed_stops[-1][1][1]:02x}{parsed_stops[-1][1][2]:02x}"

    out = Text()
    for line in lines:
        centered = line.center(term_width)
        n = len(centered)
        for i, char in enumerate(centered):
            t = i / max(n - 1, 1)
            color = get_color_for_t(t)
            out.append(char, Style(color=color, bold='bold' in style, italic='italic' in style))
        out.append("\n")
    return out

def render_table_to_string(table, width=None):
    console_file = io.StringIO()
    console = Console(file=console_file, width=width or shutil.get_terminal_size((80, 20)).columns)
    console.print(table)
    return console_file.getvalue()

def build_boxed_grid(contents):
    rows = 3
    cols = 3
    total_cells = rows * cols

    contents = (contents + [""] * total_cells)[:total_cells]
    table = Table.grid(padding=(0, 3), expand=False)

    for _ in range(cols):
        table.add_column(justify="center")

    for row_idx in range(rows):
        row_cells = []
        for col_idx in range(cols):
            idx = row_idx * cols + col_idx
            cell_text = contents[idx]

            cell_panel = Panel(f"{idx + 1}) {cell_text}", padding=(0, 3), border_style="white")
            row_cells.append(cell_panel)
        table.add_row(*row_cells)

    return table

def build_render_cache(console, buttons):
    width = console.size.width
    title = gradient_text(
        signature + "\n" + quote + "\n" + lineDivider,
        [(0, "#192fd7"), (0.6, "#FFECB3"), (1, "#192fd7")],
        width,
        style="bold italic"
    )

    table_cache = {}
    for sel in range(1, 10):
        newButtons = buttons.copy()
        newButtons[sel - 1] = f"{newButtons[sel - 1]} (x)"
        table = gradient_text(
            render_table_to_string(build_boxed_grid(newButtons)),
            [(0, "#a1abff"), (0.6, "#FFECB3"), (1, "#a1abff")],
            width
        )
        table_cache[sel] = table
    return title, table_cache

async def consoleMain():
    global currentInput
    global entered
    global listening
    global chosenClient

    os.system("cls")

    console = Console()
    key_queue = asyncio.Queue()
    loop = asyncio.get_event_loop()

    buttons = [
        "Set Client", "Grind Pickaxe", "Grind Gear", 
        "Grind Ore", "Grind Layer", "Modify Task", 
        "View Log", "View Statistics", "Load Script"
    ]

    selected = 1
    
    currentInput = ""
    
    entered = False
    listening = True

    if sys.platform == "win32":
        listener_thread = threading.Thread(target=windows_keypress_listener, args=(key_queue, loop), daemon=True)
    else:
        listener_thread = threading.Thread(target=unix_keypress_listener, args=(key_queue, loop), daemon=True)
    
    listener_thread.start()

    width = console.size.width
    last_width = width

    title, table_cache = build_render_cache(console, buttons)

    last_selected = None

    while True:
        entered = False
        selected = 1; last_selected = 0
        
        os.system("cls")
        
        with Live(console=console, refresh_per_second=10, screen=True) as live:
            while not entered:
                width_now = console.size.width
                if width_now != last_width:
                    title, table_cache = build_render_cache(console, buttons)
                    last_width = width_now
                    last_selected = None
                
                selected = int(currentInput) if currentInput != "" else 1
                
                if selected < 1 or selected > len(buttons):
                    currentInput = currentInput[-1] if selected > len(buttons) else ""
                    selected = 1 if currentInput == "" or int(currentInput) == 0 else int(currentInput)

                if selected != last_selected:
                    group = Group(title, table_cache[selected])
                    live.update(group)
                    last_selected = selected

                await asyncio.sleep(0.1)
                    
        chosen = buttons[selected - 1]

        if chosen == "Set Client":
            if len(connected_users) <= 0:
                console.print("[#a1abff]There are no connected clients right now.")
                input()
            else:
                keys = connected_users.keys()
                userList = '\n'.join(f"{index+1}) {name}" for index, name in enumerate(keys))
                console.print(f"[#a1abff]Connected Clients (current client: {'none' if chosenClient == None else chosenClient.name}):\n{userList}")
                console.print("\n[#a1abff]Set Client: ")
                response = input()
                
                isInt = True
                success = False
                    
                try:
                    int(response)
                except:
                    isInt = False
            
                if isInt:
                    if int(response) <= len(keys) and int(response) > 0:
                        chosenClient = connected_users[list(keys)[int(response) - 1]]
                        success = True
                else:
                    if response in connected_users:
                        chosenClient = connected_users[response]
                        success = True
                            
                entered = not success

                if success:
                    console.print(f"[#a1abff]Set client to {chosenClient.name}!")
                else:
                    console.print("[#a1abff]Invalid client.")
                    
                input()
        elif chosenClient != None:
            gameInformation = chosenClient.invoke_threadsafe({
                "packet": "retrieve_game_information"
            })
            
            if not gameInformation or not "data" in gameInformation:
                console.print("[#a1abff]Failed to retrieve game information, please retry.")
                input(); continue
            
            gameInformation = gameInformation["data"]
            
            if chosen == "Grind Pickaxe" or chosen == "Grind Gear":
                table = Table()
                table.add_column("Name")
                table.add_column("Tier")
                table.add_column("World")
                
                index = chosen.removeprefix("Grind ").lower() + "s"
                
                for key in sorted(gameInformation[index], key=lambda k: gameInformation[index][k]['tier'], reverse=True):
                    data = gameInformation[index][key]
                    world = data.get("world")
                    
                    if world is None or not world in WORLDS:
                        continue
                    
                    table.add_row(data["name"], str(data["tier"]), world.replace('_', ' ').title())
                    
                console.print(table, style="#a1abff")
                
                console.print(f"[#a1abff]Select a {index[:-1]} to grind:")
                item = input()
                
                if not item.lower().replace(" ", "_").replace("'", "") in gameInformation[index]:
                    console.print(f"[#a1abff]{index[:-1].title()} not found.")
                    input(); continue
                
                if chosenClient is None:
                    console.print("[#a1abff]Selected client has left the game.")
                    input(); continue
                
                status = chosenClient.invoke_threadsafe({
                    "packet": "grind",
                    "type": "grind",
                    "item_type": chosen.removeprefix("Grind ").lower(),
                    "item_name": item.lower().replace(" ", "_").replace("'", ""),
                    "goal": gameInformation[index][item.lower().replace(" ", "_").replace("'", "")]["recipe"]
                })
                
                if status["status"] == "running":
                    console.print(f"[#a1abff]Now grinding {item}!")
                elif status["status"] == "queued":
                    console.print(f"[#a1abff]Queued {item}! Please use `Modify Task` if you want to cancel the current task.")
            elif chosen == "Grind Layer":
                print(gameInformation["regions"])
            elif chosen == "Grind/Add Ores":
                print(gameInformation["ores"])
            elif chosen == "Modify Task":
                await chosenClient.send({
                    "packet": "cancel"
                })
                
                console.print(f"[#a1abff]Cancelled task, ")
            
            input()
        else:
            console.print("[#a1abff]Please select a client!")
            input()

def startConsole():
    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)
    loop.run_until_complete(consoleMain())
    loop.close()

# ------------------------------------------------
# Entry Point
# ------------------------------------------------

async def main():
    flask_server = threading.Thread(target=flaskMain, daemon=True)
    flask_server.start()

    console_thread = threading.Thread(target=startConsole, daemon=True)
    console_thread.start()

    await socketMain()

if __name__ == "__main__":
    asyncio.run(main())