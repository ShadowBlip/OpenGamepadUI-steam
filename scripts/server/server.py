#!/usr/bin/python
import asyncio

from jsonrpcserver import method, Success, Result, async_dispatch
import websockets
import json
import vdf

from steamctl.clients import CachingSteamClient
from steamctl.utils.storage import UserDataFile
from steam.enums import EResult, EOSType, EPersonaState

client = CachingSteamClient()


@method
async def load_vdf(path) -> Result:
    data = vdf.load(open(path))
    return Success(data)


@method
async def is_logged_in() -> Result:
    print("[server.py] is_logged_in(): ", client.logged_on)
    return Success(client.logged_on)


@method
async def set_credential_location(path) -> Result:
    print("[server.py] set_credential_location('" + path + "')")
    return Success(client.set_credential_location(path))


@method
async def relogin_available() -> Result:
    print("[server.py] relogin_available(): ", client.relogin_available)
    lastFile = UserDataFile("client/lastuser")
    if not lastFile.exists():
        return Success(False)
    user = lastFile.read_text()
    userkey = UserDataFile("client/%s.key" % user)
    if not userkey.exists():
        return Success(False)

    client.username = user
    client.login_key = userkey.read_text()
    return Success(True)


@method
async def relogin() -> Result:
    response = client.relogin()
    print("[server.py] relogin(): ", response)
    return Success(response)


@method
async def login(
    user,
    password="",
    login_key=None,
    auth_code=None,
    two_factor_code=None,
    login_id=None,
) -> Result:
    result = client.login(
        user, password, login_key, auth_code, two_factor_code, login_id
    )
    print("[server.py] login(%s): " % user, result)
    lastFile = UserDataFile("client/lastuser")
    lastFile.write_text(user)
    return Success(result)


# https://github.com/ValvePython/steamctl/blob/master/steamctl/commands/apps/gcmds.py#L53
@method
async def get_product_info(
    apps=[],
    packages=[],
    meta_data_only=False,
    raw=False,
    auto_access_tokens=True,
    timeout=15,
) -> Result:
    print("[server.py] get_product_info(): ")
    client.check_for_changes()

    data = client.get_product_info(apps=apps)
    if not data:
        print("No results")
        return Success({})

    data = data["apps"]

    # Only return the data we actually care about
    apps = {}
    for app_id, app in data.items():
        if not "common" in app:
            continue
        if not "type" in app["common"]:
            continue
        if app["common"]["type"] != "game":
            continue
        apps[app_id] = app["common"]

    return Success(data)


@method
async def get_product_name(apps=[]) -> Result:
    print("[server.py] get_product_names()")
    client.check_for_changes()
    data = client.get_product_info(apps=apps)
    if not data:
        print("No results")
        return Success({})

    data = data["apps"]

    # Only return the data we actually care about
    apps = {}
    for app_id, app in data.items():
        if not "common" in app:
            continue
        if not "type" in app["common"]:
            continue
        if app["common"]["type"].lower() != "game":
            continue
        if not "name" in app["common"]:
            continue
        apps[app_id] = app["common"]["name"]

    return Success(apps)


@method
async def list_apps() -> Result:
    cdn_client = client.get_cdnclient()
    cdn_client.load_licenses()
    app_ids = sorted(cdn_client.licensed_app_ids)
    print("[server.py] list_apps(): ", app_ids)
    return Success(list(app_ids))


async def main(websocket, path):
    async for message in websocket:
        response = await async_dispatch(message)
        await websocket.send(response)


if __name__ == "__main__":
    # 57348
    start_server = websockets.serve(main, "localhost", 5000, max_size=None)
    asyncio.get_event_loop().run_until_complete(start_server)
    asyncio.get_event_loop().run_forever()
