#!/usr/bin/env bash
#
# This software is in the public domain under CC0 1.0 Universal plus a
# Grant of Patent License.
#
# To the extent possible under law, the author(s) have dedicated all
# copyright and related and neighboring rights to this software to the
# public domain worldwide. This software is distributed without any
# warranty.
#
# You should have received a copy of the CC0 Public Domain Dedication
# along with this software (see the LICENSE.md file). If not, see
# <http://creativecommons.org/publicdomain/zero/1.0/>.
#
set -euo pipefail
if [ -f /run/secrets/openvla_hf_token ]; then
    export HUGGING_FACE_HUB_TOKEN="$(cat /run/secrets/openvla_hf_token)"
    export HF_TOKEN="${HUGGING_FACE_HUB_TOKEN}"
fi

if [ -f /run/secrets/openvla_api_token ]; then
    export OPENVLA_API_TOKEN="$(cat /run/secrets/openvla_api_token)"
fi

if [ -f /opt/openvla/config/openvla.env ]; then
    set -a
    . /opt/openvla/config/openvla.env
    set +a
fi

exec uvicorn server:app --host 0.0.0.0 --port "${OPENVLA_PORT:-8000}" --app-dir /opt/openvla
