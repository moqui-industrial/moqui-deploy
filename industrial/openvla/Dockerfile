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
FROM pytorch/pytorch:2.2.0-cuda12.1-cudnn8-runtime

ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    HF_HOME=/models/huggingface \
    TRANSFORMERS_CACHE=/models/huggingface \
    HUGGINGFACE_HUB_CACHE=/models/huggingface

WORKDIR /opt/openvla

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt /tmp/requirements.txt
RUN pip install --upgrade pip && pip install -r /tmp/requirements.txt

RUN git clone --depth=1 https://github.com/openvla/openvla.git /opt/openvla/repo && \
    pip install -e /opt/openvla/repo

COPY server.py /opt/openvla/server.py
COPY entrypoint.sh /opt/openvla/entrypoint.sh
RUN chmod +x /opt/openvla/entrypoint.sh

EXPOSE 8000

ENTRYPOINT ["/opt/openvla/entrypoint.sh"]
