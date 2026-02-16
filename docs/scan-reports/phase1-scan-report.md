# Phase 1 CI Gates – Security Scan Report

**Pipeline:** Phase 1 CI Gates | **Run:** 22056083615 | **Date:** 2026-02-16T08:54Z

---

## 1. Trivy (container image)

```
Unable to find image 'aquasec/trivy:latest' locally
latest: Pulling from aquasec/trivy
f8e5590717d0: Pulling fs layer
589002ba0eae: Pulling fs layer
4260928fc830: Pulling fs layer
2f7904f2747d: Pulling fs layer
4260928fc830: Download complete
589002ba0eae: Download complete
f8e5590717d0: Download complete
589002ba0eae: Pull complete
2f7904f2747d: Download complete
f8e5590717d0: Pull complete
4260928fc830: Pull complete
2f7904f2747d: Pull complete
Digest: sha256:1c78ed1ef824ab8bb05b04359d186e4c1229d0b3e67005faacb54a7d71974f73
Status: Downloaded newer image for aquasec/trivy:latest
2026-02-16T08:54:04Z	INFO	[vulndb] Need to update DB
2026-02-16T08:54:04Z	INFO	[vulndb] Downloading vulnerability DB...
2026-02-16T08:54:04Z	INFO	[vulndb] Downloading artifact...	repo="mirror.gcr.io/aquasec/trivy-db:2"
61.23 MiB / 85.37 MiB [------------------------------------------->_________________] 71.73% ? p/s ?85.37 MiB / 85.37 MiB [----------------------------------------------------------->] 100.00% ? p/s ?85.37 MiB / 85.37 MiB [----------------------------------------------------------->] 100.00% ? p/s ?85.37 MiB / 85.37 MiB [---------------------------------------------->] 100.00% 40.23 MiB p/s ETA 0s85.37 MiB / 85.37 MiB [---------------------------------------------->] 100.00% 40.23 MiB p/s ETA 0s85.37 MiB / 85.37 MiB [---------------------------------------------->] 100.00% 40.23 MiB p/s ETA 0s85.37 MiB / 85.37 MiB [---------------------------------------------->] 100.00% 37.63 MiB p/s ETA 0s85.37 MiB / 85.37 MiB [---------------------------------------------->] 100.00% 37.63 MiB p/s ETA 0s85.37 MiB / 85.37 MiB [---------------------------------------------->] 100.00% 37.63 MiB p/s ETA 0s85.37 MiB / 85.37 MiB [---------------------------------------------->] 100.00% 35.20 MiB p/s ETA 0s85.37 MiB / 85.37 MiB [---------------------------------------------->] 100.00% 35.20 MiB p/s ETA 0s85.37 MiB / 85.37 MiB [---------------------------------------------->] 100.00% 35.20 MiB p/s ETA 0s85.37 MiB / 85.37 MiB [---------------------------------------------->] 100.00% 32.93 MiB p/s ETA 0s85.37 MiB / 85.37 MiB [---------------------------------------------->] 100.00% 32.93 MiB p/s ETA 0s85.37 MiB / 85.37 MiB [-------------------------------------------------] 100.00% 30.76 MiB p/s 3.0s2026-02-16T08:54:07Z	INFO	[vulndb] Artifact successfully downloaded	repo="mirror.gcr.io/aquasec/trivy-db:2"
2026-02-16T08:54:07Z	INFO	[vuln] Vulnerability scanning is enabled
2026-02-16T08:54:07Z	INFO	[secret] Secret scanning is enabled
2026-02-16T08:54:07Z	INFO	[secret] If your scanning is slow, please try '--scanners vuln' to disable secret scanning
2026-02-16T08:54:07Z	INFO	[secret] Please see https://trivy.dev/docs/v0.69/guide/scanner/secret#recommendation for faster secret detection
2026-02-16T08:54:08Z	INFO	Detected OS	family="alpine" version="3.19.9"
2026-02-16T08:54:08Z	INFO	[alpine] Detecting vulnerabilities...	os_version="3.19" repository="3.19" pkg_num=15
2026-02-16T08:54:08Z	INFO	Number of language-specific files	num=1
2026-02-16T08:54:08Z	INFO	[gobinary] Detecting vulnerabilities...
2026-02-16T08:54:08Z	WARN	Using severities from other vendors for some vulnerabilities. Read https://trivy.dev/docs/v0.69/guide/scanner/vulnerability#severity-selection for details.
2026-02-16T08:54:08Z	WARN	This OS version is no longer supported by the distribution	family="alpine" version="3.19.9"
2026-02-16T08:54:08Z	WARN	The vulnerability detection may be insufficient because security updates are not provided

Report Summary

┌────────────────────────────────────────────────────────────────┬──────────┬─────────────────┬─────────┐
│                             Target                             │   Type   │ Vulnerabilities │ Secrets │
├────────────────────────────────────────────────────────────────┼──────────┼─────────────────┼─────────┤
│ tasky:901d2bd72c4673753e905fa6fbef78a7b0da06ea (alpine 3.19.9) │  alpine  │        6        │    -    │
├────────────────────────────────────────────────────────────────┼──────────┼─────────────────┼─────────┤
│ app/tasky                                                      │ gobinary │        3        │    -    │
└────────────────────────────────────────────────────────────────┴──────────┴─────────────────┴─────────┘
Legend:
- '-': Not scanned
- '0': Clean (no security findings detected)


tasky:901d2bd72c4673753e905fa6fbef78a7b0da06ea (alpine 3.19.9)
==============================================================
Total: 6 (UNKNOWN: 0, LOW: 3, MEDIUM: 3, HIGH: 0, CRITICAL: 0)

┌───────────────┬────────────────┬──────────┬────────┬───────────────────┬───────────────┬──────────────────────────────────────────────────────────────┐
│    Library    │ Vulnerability  │ Severity │ Status │ Installed Version │ Fixed Version │                            Title                             │
├───────────────┼────────────────┼──────────┼────────┼───────────────────┼───────────────┼──────────────────────────────────────────────────────────────┤
│ busybox       │ CVE-2024-58251 │ MEDIUM   │ fixed  │ 1.36.1-r20        │ 1.36.1-r21    │ In netstat in BusyBox through 1.37.0, local users can launch │
│               │                │          │        │                   │               │ of networ...                                                 │
│               │                │          │        │                   │               │ https://avd.aquasec.com/nvd/cve-2024-58251                   │
│               ├────────────────┼──────────┤        │                   │               ├──────────────────────────────────────────────────────────────┤
│               │ CVE-2025-46394 │ LOW      │        │                   │               │ In tar in BusyBox through 1.37.0, a TAR archive can have     │
│               │                │          │        │                   │               │ filenames...                                                 │
│               │                │          │        │                   │               │ https://avd.aquasec.com/nvd/cve-2025-46394                   │
├───────────────┼────────────────┼──────────┤        │                   │               ├──────────────────────────────────────────────────────────────┤
│ busybox-binsh │ CVE-2024-58251 │ MEDIUM   │        │                   │               │ In netstat in BusyBox through 1.37.0, local users can launch │
│               │                │          │        │                   │               │ of networ...                                                 │
│               │                │          │        │                   │               │ https://avd.aquasec.com/nvd/cve-2024-58251                   │
│               ├────────────────┼──────────┤        │                   │               ├──────────────────────────────────────────────────────────────┤
│               │ CVE-2025-46394 │ LOW      │        │                   │               │ In tar in BusyBox through 1.37.0, a TAR archive can have     │
│               │                │          │        │                   │               │ filenames...                                                 │
│               │                │          │        │                   │               │ https://avd.aquasec.com/nvd/cve-2025-46394                   │
├───────────────┼────────────────┼──────────┤        │                   │               ├──────────────────────────────────────────────────────────────┤
│ ssl_client    │ CVE-2024-58251 │ MEDIUM   │        │                   │               │ In netstat in BusyBox through 1.37.0, local users can launch │
│               │                │          │        │                   │               │ of networ...                                                 │
│               │                │          │        │                   │               │ https://avd.aquasec.com/nvd/cve-2024-58251                   │
│               ├────────────────┼──────────┤        │                   │               ├──────────────────────────────────────────────────────────────┤
│               │ CVE-2025-46394 │ LOW      │        │                   │               │ In tar in BusyBox through 1.37.0, a TAR archive can have     │
│               │                │          │        │                   │               │ filenames...                                                 │
│               │                │          │        │                   │               │ https://avd.aquasec.com/nvd/cve-2025-46394                   │
└───────────────┴────────────────┴──────────┴────────┴───────────────────┴───────────────┴──────────────────────────────────────────────────────────────┘

app/tasky (gobinary)
====================
Total: 3 (UNKNOWN: 0, LOW: 0, MEDIUM: 2, HIGH: 1, CRITICAL: 0)

┌─────────────────────────────┬────────────────┬──────────┬──────────┬─────────────────────┬───────────────┬─────────────────────────────────────────────────────────┐
│           Library           │ Vulnerability  │ Severity │  Status  │  Installed Version  │ Fixed Version │                          Title                          │
├─────────────────────────────┼────────────────┼──────────┼──────────┼─────────────────────┼───────────────┼─────────────────────────────────────────────────────────┤
│ github.com/dgrijalva/jwt-go │ CVE-2020-26160 │ HIGH     │ affected │ v3.2.0+incompatible │               │ jwt-go: access restriction bypass vulnerability         │
│                             │                │          │          │                     │               │ https://avd.aquasec.com/nvd/cve-2020-26160              │
├─────────────────────────────┼────────────────┼──────────┼──────────┼─────────────────────┼───────────────┼─────────────────────────────────────────────────────────┤
│ github.com/gin-gonic/gin    │ CVE-2023-26125 │ MEDIUM   │ fixed    │ v1.8.1              │ 1.9.0         │ golang-github-gin-gonic-gin: Improper Input Validation  │
│                             │                │          │          │                     │               │ https://avd.aquasec.com/nvd/cve-2023-26125              │
│                             ├────────────────┤          │          │                     ├───────────────┼─────────────────────────────────────────────────────────┤
│                             │ CVE-2023-29401 │          │          │                     │ 1.9.1         │ golang-github-gin-gonic-gin: Gin Web Framework does not │
│                             │                │          │          │                     │               │ properly sanitize filename parameter of                 │
│                             │                │          │          │                     │               │ Context.FileAttachment...                               │
│                             │                │          │          │                     │               │ https://avd.aquasec.com/nvd/cve-2023-29401              │
└─────────────────────────────┴────────────────┴──────────┴──────────┴─────────────────────┴───────────────┴─────────────────────────────────────────────────────────┘
```

## 2. Trivy (filesystem – tasky-main)

```

Report Summary

┌────────┬───────┬─────────────────┬─────────┐
│ Target │ Type  │ Vulnerabilities │ Secrets │
├────────┼───────┼─────────────────┼─────────┤
│ go.mod │ gomod │        3        │    -    │
└────────┴───────┴─────────────────┴─────────┘
Legend:
- '-': Not scanned
- '0': Clean (no security findings detected)


go.mod (gomod)
==============
Total: 3 (UNKNOWN: 0, LOW: 0, MEDIUM: 2, HIGH: 1, CRITICAL: 0)

┌─────────────────────────────┬────────────────┬──────────┬──────────┬─────────────────────┬───────────────┬─────────────────────────────────────────────────────────┐
│           Library           │ Vulnerability  │ Severity │  Status  │  Installed Version  │ Fixed Version │                          Title                          │
├─────────────────────────────┼────────────────┼──────────┼──────────┼─────────────────────┼───────────────┼─────────────────────────────────────────────────────────┤
│ github.com/dgrijalva/jwt-go │ CVE-2020-26160 │ HIGH     │ affected │ v3.2.0+incompatible │               │ jwt-go: access restriction bypass vulnerability         │
│                             │                │          │          │                     │               │ https://avd.aquasec.com/nvd/cve-2020-26160              │
├─────────────────────────────┼────────────────┼──────────┼──────────┼─────────────────────┼───────────────┼─────────────────────────────────────────────────────────┤
│ github.com/gin-gonic/gin    │ CVE-2023-26125 │ MEDIUM   │ fixed    │ v1.8.1              │ 1.9.0         │ golang-github-gin-gonic-gin: Improper Input Validation  │
│                             │                │          │          │                     │               │ https://avd.aquasec.com/nvd/cve-2023-26125              │
│                             ├────────────────┤          │          │                     ├───────────────┼─────────────────────────────────────────────────────────┤
│                             │ CVE-2023-29401 │          │          │                     │ 1.9.1         │ golang-github-gin-gonic-gin: Gin Web Framework does not │
│                             │                │          │          │                     │               │ properly sanitize filename parameter of                 │
│                             │                │          │          │                     │               │ Context.FileAttachment...                               │
│                             │                │          │          │                     │               │ https://avd.aquasec.com/nvd/cve-2023-29401              │
└─────────────────────────────┴────────────────┴──────────┴──────────┴─────────────────────┴───────────────┴─────────────────────────────────────────────────────────┘
```

## 3. Hadolint (Dockerfile)

```
```

## 4. Semgrep (SAST – tasky-main)

```
               
               
┌─────────────┐
│ Scan Status │
└─────────────┘
  Scanning 20 files tracked by git with 250 Code rules:
                                                                                                                        
  Language      Rules   Files          Origin      Rules                                                                
 ─────────────────────────────        ───────────────────                                                               
  <multilang>       9      11          Community     250                                                                
  go               53       6                                                                                           
  js               20       2                                                                                           
  dockerfile        1       1                                                                                           
                                                                                                                        
                    
                    
┌──────────────────┐
│ 16 Code Findings │
└──────────────────┘
                                            
    tasky-main/controllers/userController.go
    ❯❱ go.lang.security.audit.net.cookie-missing-httponly.cookie-missing-httponly
          A session cookie was detected without setting the 'HttpOnly' flag. The 'HttpOnly' flag for cookies
          instructs the browser to forbid client-side scripts from reading the cookie which mitigates XSS   
          attacks. Set the 'HttpOnly' flag by setting 'HttpOnly' to 'true' in the Cookie.                   
          Details: https://sg.run/b73e                                                                      
                                                                                                            
           ▶▶┆ Autofix ▶ http.Cookie{ Name:    "token", Value:   token, Expires: expirationTime, }
           66┆ http.SetCookie(c.Writer, &http.Cookie{
           67┆    Name:    "token",
           68┆    Value:   token,
           69┆    Expires: expirationTime,
           70┆ })
   
    ❯❱ go.lang.security.audit.net.cookie-missing-secure.cookie-missing-secure
          A session cookie was detected without setting the 'Secure' flag. The 'secure' flag for cookies
          prevents the client from transmitting the cookie over insecure channels such as HTTP. Set the 
          'Secure' flag by setting 'Secure' to 'true' in the Options struct.                            
          Details: https://sg.run/N4G7                                                                  
                                                                                                        
           ▶▶┆ Autofix ▶ http.Cookie{ Name:    "token", Value:   token, Expires: expirationTime, }
           66┆ http.SetCookie(c.Writer, &http.Cookie{
           67┆    Name:    "token",
           68┆    Value:   token,
           69┆    Expires: expirationTime,
           70┆ })
   
    ❯❱ go.lang.security.audit.net.cookie-missing-httponly.cookie-missing-httponly
          A session cookie was detected without setting the 'HttpOnly' flag. The 'HttpOnly' flag for cookies
          instructs the browser to forbid client-side scripts from reading the cookie which mitigates XSS   
          attacks. Set the 'HttpOnly' flag by setting 'HttpOnly' to 'true' in the Cookie.                   
          Details: https://sg.run/b73e                                                                      
                                                                                                            
           ▶▶┆ Autofix ▶ http.Cookie{ Name : "userID", Value : userId, Expires: expirationTime, }
           72┆ http.SetCookie(c.Writer, &http.Cookie{
           73┆    Name : "userID",
           74┆    Value : userId,
           75┆    Expires: expirationTime,
           76┆ })
   
    ❯❱ go.lang.security.audit.net.cookie-missing-secure.cookie-missing-secure
          A session cookie was detected without setting the 'Secure' flag. The 'secure' flag for cookies
          prevents the client from transmitting the cookie over insecure channels such as HTTP. Set the 
          'Secure' flag by setting 'Secure' to 'true' in the Options struct.                            
          Details: https://sg.run/N4G7                                                                  
                                                                                                        
           ▶▶┆ Autofix ▶ http.Cookie{ Name : "userID", Value : userId, Expires: expirationTime, }
           72┆ http.SetCookie(c.Writer, &http.Cookie{
           73┆    Name : "userID",
           74┆    Value : userId,
           75┆    Expires: expirationTime,
           76┆ })
   
    ❯❱ go.lang.security.audit.net.cookie-missing-httponly.cookie-missing-httponly
          A session cookie was detected without setting the 'HttpOnly' flag. The 'HttpOnly' flag for cookies
          instructs the browser to forbid client-side scripts from reading the cookie which mitigates XSS   
          attacks. Set the 'HttpOnly' flag by setting 'HttpOnly' to 'true' in the Cookie.                   
          Details: https://sg.run/b73e                                                                      
                                                                                                            
           ▶▶┆ Autofix ▶ http.Cookie{ Name : "username", Value : username, Expires: expirationTime, }
           77┆ http.SetCookie(c.Writer, &http.Cookie{
           78┆    Name : "username",
           79┆    Value : username,
           80┆    Expires: expirationTime,
           81┆ })
   
    ❯❱ go.lang.security.audit.net.cookie-missing-secure.cookie-missing-secure
          A session cookie was detected without setting the 'Secure' flag. The 'secure' flag for cookies
          prevents the client from transmitting the cookie over insecure channels such as HTTP. Set the 
          'Secure' flag by setting 'Secure' to 'true' in the Options struct.                            
          Details: https://sg.run/N4G7                                                                  
                                                                                                        
           ▶▶┆ Autofix ▶ http.Cookie{ Name : "username", Value : username, Expires: expirationTime, }
           77┆ http.SetCookie(c.Writer, &http.Cookie{
           78┆    Name : "username",
           79┆    Value : username,
           80┆    Expires: expirationTime,
           81┆ })
   
    ❯❱ go.lang.security.audit.net.cookie-missing-httponly.cookie-missing-httponly
          A session cookie was detected without setting the 'HttpOnly' flag. The 'HttpOnly' flag for cookies
          instructs the browser to forbid client-side scripts from reading the cookie which mitigates XSS   
          attacks. Set the 'HttpOnly' flag by setting 'HttpOnly' to 'true' in the Cookie.                   
          Details: https://sg.run/b73e                                                                      
                                                                                                            
           ▶▶┆ Autofix ▶ http.Cookie{ Name:    "token", Value:   token, Expires: expirationTime, }
          133┆ http.SetCookie(c.Writer, &http.Cookie{
          134┆    Name:    "token",
          135┆    Value:   token,
          136┆    Expires: expirationTime,
          137┆ })
   
    ❯❱ go.lang.security.audit.net.cookie-missing-secure.cookie-missing-secure
          A session cookie was detected without setting the 'Secure' flag. The 'secure' flag for cookies
          prevents the client from transmitting the cookie over insecure channels such as HTTP. Set the 
          'Secure' flag by setting 'Secure' to 'true' in the Options struct.                            
          Details: https://sg.run/N4G7                                                                  
                                                                                                        
           ▶▶┆ Autofix ▶ http.Cookie{ Name:    "token", Value:   token, Expires: expirationTime, }
          133┆ http.SetCookie(c.Writer, &http.Cookie{
          134┆    Name:    "token",
          135┆    Value:   token,
          136┆    Expires: expirationTime,
          137┆ })
   
    ❯❱ go.lang.security.audit.net.cookie-missing-httponly.cookie-missing-httponly
          A session cookie was detected without setting the 'HttpOnly' flag. The 'HttpOnly' flag for cookies
          instructs the browser to forbid client-side scripts from reading the cookie which mitigates XSS   
          attacks. Set the 'HttpOnly' flag by setting 'HttpOnly' to 'true' in the Cookie.                   
          Details: https://sg.run/b73e                                                                      
                                                                                                            
           ▶▶┆ Autofix ▶ http.Cookie{ Name : "userID", Value : userId, Expires: expirationTime, }
          139┆ http.SetCookie(c.Writer, &http.Cookie{
          140┆    Name : "userID",
          141┆    Value : userId,
          142┆    Expires: expirationTime,
          143┆ })
   
    ❯❱ go.lang.security.audit.net.cookie-missing-secure.cookie-missing-secure
          A session cookie was detected without setting the 'Secure' flag. The 'secure' flag for cookies
          prevents the client from transmitting the cookie over insecure channels such as HTTP. Set the 
          'Secure' flag by setting 'Secure' to 'true' in the Options struct.                            
          Details: https://sg.run/N4G7                                                                  
                                                                                                        
           ▶▶┆ Autofix ▶ http.Cookie{ Name : "userID", Value : userId, Expires: expirationTime, }
          139┆ http.SetCookie(c.Writer, &http.Cookie{
          140┆    Name : "userID",
          141┆    Value : userId,
          142┆    Expires: expirationTime,
          143┆ })
   
    ❯❱ go.lang.security.audit.net.cookie-missing-httponly.cookie-missing-httponly
          A session cookie was detected without setting the 'HttpOnly' flag. The 'HttpOnly' flag for cookies
          instructs the browser to forbid client-side scripts from reading the cookie which mitigates XSS   
          attacks. Set the 'HttpOnly' flag by setting 'HttpOnly' to 'true' in the Cookie.                   
          Details: https://sg.run/b73e                                                                      
                                                                                                            
           ▶▶┆ Autofix ▶ http.Cookie{ Name : "username", Value : username, Expires: expirationTime, }
          144┆ http.SetCookie(c.Writer, &http.Cookie{
          145┆    Name : "username",
          146┆    Value : username,
          147┆    Expires: expirationTime,
          148┆ })
   
    ❯❱ go.lang.security.audit.net.cookie-missing-secure.cookie-missing-secure
          A session cookie was detected without setting the 'Secure' flag. The 'secure' flag for cookies
          prevents the client from transmitting the cookie over insecure channels such as HTTP. Set the 
          'Secure' flag by setting 'Secure' to 'true' in the Options struct.                            
          Details: https://sg.run/N4G7                                                                  
                                                                                                        
           ▶▶┆ Autofix ▶ http.Cookie{ Name : "username", Value : username, Expires: expirationTime, }
          144┆ http.SetCookie(c.Writer, &http.Cookie{
          145┆    Name : "username",
          146┆    Value : username,
          147┆    Expires: expirationTime,
          148┆ })
   
    ❯❱ go.lang.security.audit.net.cookie-missing-httponly.cookie-missing-httponly
          A session cookie was detected without setting the 'HttpOnly' flag. The 'HttpOnly' flag for cookies
          instructs the browser to forbid client-side scripts from reading the cookie which mitigates XSS   
          attacks. Set the 'HttpOnly' flag by setting 'HttpOnly' to 'true' in the Cookie.                   
          Details: https://sg.run/b73e                                                                      
                                                                                                            
           ▶▶┆ Autofix ▶ http.Cookie{ Name : "userID", Value : userId, Expires: expirationTime, }
          151┆ http.SetCookie(c.Writer, &http.Cookie{
          152┆    Name : "userID",
          153┆    Value : userId,
          154┆    Expires: expirationTime,
          155┆ })
   
    ❯❱ go.lang.security.audit.net.cookie-missing-secure.cookie-missing-secure
          A session cookie was detected without setting the 'Secure' flag. The 'secure' flag for cookies
          prevents the client from transmitting the cookie over insecure channels such as HTTP. Set the 
          'Secure' flag by setting 'Secure' to 'true' in the Options struct.                            
          Details: https://sg.run/N4G7                                                                  
                                                                                                        
           ▶▶┆ Autofix ▶ http.Cookie{ Name : "userID", Value : userId, Expires: expirationTime, }
          151┆ http.SetCookie(c.Writer, &http.Cookie{
          152┆    Name : "userID",
          153┆    Value : userId,
          154┆    Expires: expirationTime,
          155┆ })
   
    ❯❱ go.lang.security.audit.net.cookie-missing-httponly.cookie-missing-httponly
          A session cookie was detected without setting the 'HttpOnly' flag. The 'HttpOnly' flag for cookies
          instructs the browser to forbid client-side scripts from reading the cookie which mitigates XSS   
          attacks. Set the 'HttpOnly' flag by setting 'HttpOnly' to 'true' in the Cookie.                   
          Details: https://sg.run/b73e                                                                      
                                                                                                            
           ▶▶┆ Autofix ▶ http.Cookie{ Name : "username", Value : username, Expires: expirationTime, }
          156┆ http.SetCookie(c.Writer, &http.Cookie{
          157┆    Name : "username",
          158┆    Value : username,
          159┆    Expires: expirationTime,
          160┆ })
   
    ❯❱ go.lang.security.audit.net.cookie-missing-secure.cookie-missing-secure
          A session cookie was detected without setting the 'Secure' flag. The 'secure' flag for cookies
          prevents the client from transmitting the cookie over insecure channels such as HTTP. Set the 
          'Secure' flag by setting 'Secure' to 'true' in the Options struct.                            
          Details: https://sg.run/N4G7                                                                  
                                                                                                        
           ▶▶┆ Autofix ▶ http.Cookie{ Name : "username", Value : username, Expires: expirationTime, }
          156┆ http.SetCookie(c.Writer, &http.Cookie{
          157┆    Name : "username",
          158┆    Value : username,
          159┆    Expires: expirationTime,
          160┆ })

                
                
┌──────────────┐
│ Scan Summary │
└──────────────┘
✅ Scan completed successfully.
 • Findings: 16 (16 blocking)
 • Rules run: 83
 • Targets scanned: 20
 • Parsed lines: ~100.0%
 • Scan was limited to files tracked by git
 • For a detailed list of skipped files and lines, run semgrep with the --verbose flag
Ran 83 rules on 20 files: 16 findings.
```

## 5. Terraform validate & format

Terraform validate and format check passed (see terraform-validate job).
