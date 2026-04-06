FROM python:3.11-slim

WORKDIR /app
ENV PYTHONUNBUFFERED=1 \
	PYTHONDONTWRITEBYTECODE=1

RUN useradd --create-home --shell /usr/sbin/nologin appuser

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY main.py .

USER appuser

CMD ["python", "-u", "main.py"]
