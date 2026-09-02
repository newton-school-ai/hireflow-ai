FROM python:3.11-slim

# Install system dependencies (LaTeX for resume generation + Playwright deps).
# base_template.tex only uses geometry/parskip/hyperref/lmodern/xcolor/titlesec
# (see src/templates/resume_latex/) — texlive-latex-extra covers titlesec.
# texlive-fonts-extra is NOT used by the template; it's a huge, unused
# package whose font-cache postinst step reliably OOM-kills the build under
# Docker Desktop's default VM memory limit.
# --no-install-recommends matters here more than usual: without it, apt pulls
# in default-jre, GTK, X11 and a DVI/PS toolchain (~600MB extra) that a
# headless xelatex build never touches — that alone tripled build time and
# caused an apt-get run long enough to hit a mid-build DNS blip.
RUN apt-get update && apt-get install -y --no-install-recommends \
    texlive-xetex \
    texlive-fonts-recommended \
    texlive-latex-extra \
    curl \
    wget \
    gnupg \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Install Playwright browsers
RUN playwright install chromium --with-deps

# Copy application code
COPY . .

# Expose FastAPI port
EXPOSE 8000

# Apply migrations against whatever DATABASE_URL the container gets, then
# start the API server — a fresh `db` volume has no tables otherwise.
CMD ["sh", "-c", "alembic upgrade head && uvicorn src.api.main:app --host 0.0.0.0 --port 8000"]
