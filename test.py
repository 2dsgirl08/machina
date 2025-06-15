import asyncio
import websockets
import json
import random
import string

def random_username(length=8):
    return ''.join(random.choices(string.ascii_letters + string.digits, k=length))

def random_ores():
    return {
        "iron": random.randint(1, 30),
        "gold": random.randint(0, 10),
        "diamond": random.randint(0, 5)
    }

async def client():
    uri = "ws://localhost:8765"
    async with websockets.connect(uri) as websocket:
        # Wait for server's identify request
        message = await websocket.recv()
        print(f"Server says: {message}")

        if message == "identify":
            username = random_username()
            await websocket.send(json.dumps({
                "type": "identify",
                "username": username
            }))
            print(f"Sent identify as {username}")

        # Now listen/respond to incoming requests
        async for msg in websocket:
            data = json.loads(msg)
            print(f"Received request: {data}")

            if data.get("type") == "get_ores":
                response = {
                    "type": "ores_data",
                    "ores": random_ores()
                }
                await websocket.send(json.dumps(response))
                print(f"Sent ores data: {response['ores']}")

asyncio.run(client())
