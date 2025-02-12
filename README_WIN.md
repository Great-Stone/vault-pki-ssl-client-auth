# Vault PKI Demo - Browser auth (Windows 11)

## 준비사항

필수 설치 및 실행 환경은 다음과 같습니다:

- Vault, Nomad, Docker가 실행 가능한 Windows 11 환경
  - Vault 설치: [https://developer.hashicorp.com/vault/install](https://developer.hashicorp.com/vault/install)
  - Nomad 설치: [https://developer.hashicorp.com/nomad/install](https://developer.hashicorp.com/nomad/install)
  - Docker Desktop for Windows 설치
- Python 3 및 필요한 패키지 (flask, hvac, cryptography)
- Windows PowerShell 또는 Command Prompt

## 1. Setup ENV

PowerShell을 관리자 권한으로 실행하여 다음 환경변수를 설정합니다:

```powershell
$env:NOMAD_ADDR = 'http://127.0.0.1:4646'
$env:VAULT_ADDR = 'http://127.0.0.1:8200'
$env:VAULT_TOKEN = 'root'
$env:NOMAD_POLICY = 'nomad-server'
```

## 2. Run Vault

새 PowerShell 창을 열어 실행:

```powershell
vault server -dev -dev-listen-address=0.0.0.0:8200 -dev-root-token-id=$env:VAULT_TOKEN
```

## 3. Setup Vault PKI

```powershell
vault secrets enable pki
vault secrets tune -max-lease-ttl=87600h pki
vault write pki/root/generate/internal `
  key_bits=2048 `
  private_key_format=pem `
  signature_bits=256 `
  country=KR `
  province=Seoul `
  locality=KR `
  organization=COMPANY `
  ou=DEV `
  common_name=example.com `
  ttl=87600h

vault write pki/config/urls `
  issuing_certificates="http://127.0.0.1:8200/v1/pki/ca" `
  crl_distribution_points="http://127.0.0.1:8200/v1/pki/crl"

vault write pki/roles/example-dot-com `
  allowed_domains=example.com `
  allow_subdomains=true `
  max_ttl=72h

vault write pki/roles/user-auth `
  allowed_domains=example.com `
  allow_subdomains=true `
  client_flag=true `
  max_ttl=72h

# PowerShell에서 Here-String 사용
@"
path "pki/issue/*" {
  capabilities = [ "create", "read", "update", "delete", "list", "sudo" ]
}
"@ | vault policy write pki_policy -
```

## 4. Vault Policy & Token for Nomad

```powershell
@"
path "auth/token/create/nomad-cluster" {
  capabilities = ["update"]
}

path "auth/token/roles/nomad-cluster" {
  capabilities = ["read"]
}

path "auth/token/lookup-self" {
  capabilities = ["read"]
}

path "auth/token/lookup" {
  capabilities = ["update"]
}

path "auth/token/revoke-accessor" {
  capabilities = ["update"]
}

path "sys/capabilities-self" {
  capabilities = ["update"]
}

path "auth/token/renew-self" {
  capabilities = ["update"]
}
"@ | vault policy write $env:NOMAD_POLICY -
```

## 5. Run Nomad with Vault Token

새 PowerShell 창에서 실행:

```powershell
vault write auth/token/roles/nomad-cluster allowed_policies="pki_policy" disallowed_policies="$env:NOMAD_POLICY" token_explicit_max_ttl=0 orphan=true token_period="259200" renewable=true

# 토큰 생성 및 임시 파일에 저장
vault token create -field token -policy $env:NOMAD_POLICY -period 72h -orphan | Out-File -FilePath "$env:TEMP\token.txt"

# 토큰을 사용하여 Nomad 실행
nomad agent -dev -vault-enabled=true -vault-address=http://127.0.0.1:8200 -vault-token=(Get-Content "$env:TEMP\token.txt") -vault-tls-skip-verify=true -vault-create-from-role=nomad-cluster
```

## 6. Setup Vault Userpass

```powershell
vault auth enable userpass
vault write auth/userpass/users/user1 password=password policies=pki
```

## 7. Nginx run on Nomad with mTLS configuration

```powershell
nomad job run nginx.job.hcl
```

## 8. Set hosts file and browser check

Windows의 hosts 파일을 관리자 권한으로 수정합니다:
1. 메모장을 관리자 권한으로 실행
2. `C:\Windows\System32\drivers\etc\hosts` 파일을 열기
3. 다음 줄 추가:
```
127.0.0.1   service-a.example.com
```

브라우저에서 확인:
- [https://service-a.example.com](https://service-a.example.com) (허용)
- [https://service-a.example.com/secure](https://service-a.example.com/secure) (거부)

## 9. Get pkcs12 client key

`pk12-app` 디렉토리에서 다음 명령어 실행:

```powershell
python -m pip install flask hvac cryptography
python app.py
```

[http://127.0.0.1:8888](http://127.0.0.1:8888)에 접속하여:
1. Username: `user1`
2. Password: `password`
3. 인증서 비밀번호 입력
4. 다운로드된 *.pk12 파일을 Windows 인증서 저장소에 등록

## 10. Go to ssl_client_verify location

[https://service-a.example.com/secure](https://service-a.example.com/secure)에 접속하면 Windows 인증서 선택 대화상자가 표시됩니다. 등록한 인증서를 선택하면 보안 페이지에 접근할 수 있습니다.