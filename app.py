from flask import Flask, request, jsonify
import logging

app = Flask(__name__)

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def get_client_ip():
    """
    Get the client's real IP address, considering various proxy headers
    """
    # Check for common proxy headers in order of preference
    headers_to_check = [
        'X-Forwarded-For',
        'X-Real-IP', 
        'X-Forwarded',
        'X-Cluster-Client-IP',
        'CF-Connecting-IP'  # Cloudflare
    ]
    
    for header in headers_to_check:
        ip = request.headers.get(header)
        if ip:
            # X-Forwarded-For can contain multiple IPs, take the first one
            if ',' in ip:
                ip = ip.split(',')[0].strip()
            logger.info(f"Found IP in {header}: {ip}")
            return ip
    
    # Fallback to remote_addr
    ip = request.remote_addr
    logger.info(f"Using remote_addr: {ip}")
    return ip

def reverse_ip(ip_address):
    """
    Reverse the IP address segments
    Example: 1.2.3.4 -> 4.3.2.1
    """
    try:
        # Split by dots and reverse the order
        segments = ip_address.split('.')
        if len(segments) == 4:
            reversed_segments = segments[::-1]
            return '.'.join(reversed_segments)
        else:
            # Handle IPv6 or invalid IP format
            return f"Invalid IP format: {ip_address}"
    except Exception as e:
        logger.error(f"Error reversing IP {ip_address}: {str(e)}")
        return f"Error processing IP: {ip_address}"

@app.route('/', methods=['GET', 'POST', 'PUT', 'DELETE', 'PATCH'])
def handle_request():
    """
    Handle any HTTP request and return the reversed IP
    """
    client_ip = get_client_ip()
    reversed_ip = reverse_ip(client_ip)
    
    response_data = {
        'original_ip': client_ip,
        'reversed_ip': reversed_ip,
        'method': request.method,
        'path': request.path,
        'user_agent': request.headers.get('User-Agent', 'Unknown')
    }
    
    logger.info(f"Request from {client_ip} -> Reversed: {reversed_ip}")
    
    return jsonify(response_data), 200

@app.route('/health', methods=['GET'])
def health_check():
    """
    Health check endpoint for Kubernetes
    """
    return jsonify({'status': 'healthy', 'service': 'ip-reverse-app'}), 200

@app.route('/<path:path>', methods=['GET', 'POST', 'PUT', 'DELETE', 'PATCH'])
def catch_all(path):
    """
    Catch all other paths and still return reversed IP
    """
    client_ip = get_client_ip()
    reversed_ip = reverse_ip(client_ip)
    
    response_data = {
        'original_ip': client_ip,
        'reversed_ip': reversed_ip,
        'method': request.method,
        'path': f"/{path}",
        'user_agent': request.headers.get('User-Agent', 'Unknown')
    }
    
    logger.info(f"Request to /{path} from {client_ip} -> Reversed: {reversed_ip}")
    
    return jsonify(response_data), 200

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080, debug=False)