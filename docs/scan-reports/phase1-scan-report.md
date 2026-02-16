# Phase 1 CI Gates – Security Scan Report

**Pipeline:** Phase 1 CI Gates | **Run:** 22054908134 | **Date:** 2026-02-16T08:13Z

---

## 1. Trivy (container image)

```

Report Summary

┌────────────────────────────────────────────────────────────────┬──────────┬─────────────────┬─────────┐
│                             Target                             │   Type   │ Vulnerabilities │ Secrets │
├────────────────────────────────────────────────────────────────┼──────────┼─────────────────┼─────────┤
│ tasky:3d9617b1989b0250ab8382439211a0d5f360d6f1 (alpine 3.19.9) │  alpine  │        6        │    -    │
├────────────────────────────────────────────────────────────────┼──────────┼─────────────────┼─────────┤
│ app/tasky                                                      │ gobinary │        3        │    -    │
└────────────────────────────────────────────────────────────────┴──────────┴─────────────────┴─────────┘
Legend:
- '-': Not scanned
- '0': Clean (no security findings detected)


tasky:3d9617b1989b0250ab8382439211a0d5f360d6f1 (alpine 3.19.9)
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
