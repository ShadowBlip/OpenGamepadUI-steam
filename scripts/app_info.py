import gevent
import gevent.monkey

gevent.monkey.patch_socket()
gevent.monkey.patch_select()
gevent.monkey.patch_ssl()

import sys
import json
import codecs
import logging
import functools
from steamctl.argparser import generate_parser, nested_print_usage
from time import time
from binascii import hexlify
from contextlib import contextmanager
from steam.exceptions import SteamError
from steam.enums import EResult, EPurchaseResultDetail
from steam.client import EMsg
from steam.utils import chunks
from steamctl.clients import CachingSteamClient
from steamctl.utils.web import make_requests_session
from steamctl.utils.format import fmt_datetime
from steam.enums import ELicenseType, ELicenseFlags, EBillingType, EType
from steam.core.msg import MsgProto
from steamctl.commands.apps.enums import EPaymentMethod, EPackageStatus
from steamctl.utils.apps import get_app_names

LOG = logging.getLogger(__name__)


@contextmanager
def init_client(args):
    s = CachingSteamClient()
    s.login_from_args(args)
    yield s
    s.disconnect()


def cmd_apps_product_info(args):
    with init_client(args) as s:
        s.check_for_changes()

        if not args.skip_licenses:
            if not s.licenses and s.steam_id.type != s.steam_id.EType.AnonUser:
                s.wait_event(EMsg.ClientLicenseList, raises=False, timeout=10)

            cdn = s.get_cdnclient()
            cdn.load_licenses()

            for app_id in args.app_ids:
                if app_id not in cdn.licensed_app_ids:
                    LOG.error(
                        "No license available for App ID: %s (%s)",
                        app_id,
                        EResult.AccessDenied,
                    )
                    return 1  # error

        data = s.get_product_info(apps=args.app_ids)

        if not data:
            LOG.error("No results")
            return 1  # error

        data = data["apps"]

        json.dump(data, sys.stdout, indent=4, sort_keys=True)


if __name__ == "__main__":
    # setup login config, before loading subparsers
    parser = generate_parser(pre=True)
    args, _ = parser.parse_known_args()

    logging.basicConfig(
        format="[%(levelname)s] %(name)s: %(message)s"
        if args.log_level == "debug"
        else "[%(levelname)s] %(message)s",
        level=100
        if args.log_level == "quiet"
        else getattr(logging, args.log_level.upper()),
    )

    # reload parser, and enable auto completion
    parser = generate_parser()
    args, unknown_args = parser.parse_known_args()

    cmd_apps_product_info(args=args)
