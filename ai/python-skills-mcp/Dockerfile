# A small MCP server that runs the Python scripts of the agent skills in a container of its own: the latest Python, the
# libraries the skills need, no network (see python-skills-compose.yml), the skills read-only and one writable workspace.
FROM python:3.14-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1
WORKDIR /app
# PDF text and page images for the skills that read drawings, datasheets and certificates (pdftotext, pdftoppm, pdfinfo)
RUN apt-get update && apt-get install -y --no-install-recommends poppler-utils && rm -rf /var/lib/apt/lists/*
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY server.py .
RUN useradd --uid 10001 --no-create-home --shell /usr/sbin/nologin runner && mkdir -p /workspace && chown runner /workspace
USER runner
EXPOSE 8000
CMD ["python", "/app/server.py"]
