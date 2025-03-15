from flask import Flask, jsonify, request
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)

@app.route('/health', methods=['GET'])
def health_check():
    return jsonify({"status": "healthy"}), 200

@app.route('/detect', methods=['GET'])
def detect_threat():
    try:
        return jsonify({
            "message": "AI-powered threat detection is running",
            "status": "safe"
        }), 200
    except Exception as e:
        logger.error(f"Error in threat detection: {str(e)}")
        return jsonify({
            "error": "Internal server error",
            "message": str(e)
        }), 500

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)

