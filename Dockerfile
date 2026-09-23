# MLFlow container image

FROM python:3.12-slim

WORKDIR /app

# Copy across the pythong environment requirements file and install dependencies
COPY requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt

# Expose the port that MLFlow will run on
EXPOSE 5000

# Add a non-root user to restrict permissions and improve security
RUN useradd --uid 1000 --no-create-home mlflow_user && \
    chown -R mlflow_user:mlflow_user /app
USER 1000

# Run the MLFlow server when the container starts
CMD ["mlflow", "server", "--host", "0.0.0.0", "--port", "5000"]
