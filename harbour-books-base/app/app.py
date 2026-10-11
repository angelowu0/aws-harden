import logging
import os

import pymysql
from flask import Flask, jsonify

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("harbour-books")

app = Flask(__name__)

DB_HOST = os.environ.get("DB_HOST")
DB_USER = os.environ.get("DB_USER")
DB_PASSWORD = os.environ.get("DB_PASSWORD")
DB_NAME = os.environ.get("DB_NAME", "harbourbooks")


def get_connection():
    return pymysql.connect(
        host=DB_HOST,
        user=DB_USER,
        password=DB_PASSWORD,
        database=DB_NAME,
        connect_timeout=5,
    )


@app.route("/")
def index():
    return jsonify(status="ok", service="harbour-books")


@app.route("/health/db")
def health_db():
    try:
        conn = get_connection()
        with conn.cursor() as cur:
            cur.execute("SELECT 1")
            cur.fetchone()
        conn.close()
        return jsonify(status="ok", db="reachable")
    except Exception as exc:
        logger.error("DB health check failed: %s", exc)
        return jsonify(status="error", db="unreachable"), 500


@app.route("/error-test")
def error_test():
    logger.error("Manually triggered ERROR log line for alarm testing")
    return jsonify(status="logged"), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
