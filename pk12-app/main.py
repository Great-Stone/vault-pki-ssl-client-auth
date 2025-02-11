from flask import Flask, render_template, request, send_file
import hvac
import tempfile
import os
from cryptography import x509
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.serialization import pkcs12
from cryptography.hazmat.primitives.serialization import Encoding, PrivateFormat, NoEncryption
import io

app = Flask(__name__)

# Vault 설정
VAULT_URL = 'http://127.0.0.1:8200'  # Vault 서버 주소
PKI_ROLE = 'user-auth'  # PKI role 이름

@app.route('/', methods=['GET'])
def index():
    return render_template('index.html')

@app.route('/generate', methods=['POST'])
def generate_cert():
    try:
        username = request.form['username']
        password = request.form['password']
        cert_password = request.form['cert_password']
        
        # Vault 클라이언트 생성 및 인증
        client = hvac.Client(url=VAULT_URL)
        client.auth.userpass.login(username=username, password=password)
        
        # 인증서 common name 생성
        common_name = f"{username}.example.com"
        
        # Vault에서 인증서 발급
        cert_data = client.secrets.pki.generate_certificate(
            name=PKI_ROLE,
            common_name=common_name,
            extra_params={
                'ttl': '8760h'  # 1년
            }
        )
        
        # PEM 데이터 가져오기
        cert_pem = cert_data['data']['certificate']
        key_pem = cert_data['data']['private_key']
        ca_pem = cert_data['data']['issuing_ca']
        
        # PEM을 객체로 변환
        cert = x509.load_pem_x509_certificate(cert_pem.encode())
        private_key = serialization.load_pem_private_key(
            key_pem.encode(),
            password=None
        )
        ca_cert = x509.load_pem_x509_certificate(ca_pem.encode())
        
        # PKCS12 생성
        pkcs12_data = pkcs12.serialize_key_and_certificates(
            name=common_name.encode(),
            key=private_key,
            cert=cert,
            cas=[ca_cert],
            encryption_algorithm=serialization.BestAvailableEncryption(cert_password.encode())
        )
        
        # 메모리에서 파일 생성
        mem_file = io.BytesIO(pkcs12_data)
        mem_file.seek(0)
        
        return send_file(
            mem_file,
            mimetype='application/x-pkcs12',
            as_attachment=True,
            download_name=f'{common_name}.p12'
        )
        
    except Exception as e:
        return f'Error: {str(e)}', 400

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8888)