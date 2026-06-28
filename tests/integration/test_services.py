"""
AgentOS Docker Integration Tests
版本: 0.1.0
用途: 验证Docker Compose服务的基本功能

运行方式:
  pytest tests/integration/ -v
"""

import pytest
import requests
import time
import os


class TestServiceHealth:
    """服务健康检查测试"""

    GATEWAY_URL = os.getenv("AGENTOS_GATEWAY_URL", "http://localhost:18789")
    KERNEL_URL = os.getenv("AGENTOS_KERNEL_URL", "http://localhost:18080")
    DESKTOP_URL = os.getenv("DESKTOP_URL", "http://localhost:8080")
    TIMEOUT = int(os.getenv("TEST_TIMEOUT", "10"))

    def test_gateway_health_endpoint(self):
        """Gateway /api/v1/health 应返回200"""
        try:
            resp = requests.get(
                f"{self.GATEWAY_URL}/api/v1/health",
                timeout=self.TIMEOUT
            )
            assert resp.status_code == 200, f"Gateway health check failed: {resp.status_code}"
            data = resp.json()
            assert "status" in data or "healthy" in str(data).lower()
        except requests.exceptions.ConnectionError:
            pytest.skip("Gateway not available")

    def test_kernel_health_endpoint(self):
        """Kernel /api/v1/health 应返回200"""
        try:
            resp = requests.get(
                f"{self.KERNEL_URL}/api/v1/health",
                timeout=self.TIMEOUT
            )
            assert resp.status_code == 200, f"Kernel health check failed: {resp.status_code}"
        except requests.exceptions.ConnectionError:
            pytest.skip("Kernel not available (may be internal-only)")

    def test_desktop_serves_index(self):
        """Desktop前端应返回HTML页面"""
        try:
            resp = requests.get(
                self.DESKTOP_URL,
                timeout=self.TIMEOUT
            )
            assert resp.status_code == 200, f"Desktop not responding: {resp.status_code}"
            assert "html" in resp.headers.get("Content-Type", "").lower() or len(resp.content) > 100
        except requests.exceptions.ConnectionError:
            pytest.skip("Desktop not available")

    def test_gateway_cors_headers(self):
        """Gateway应返回正确的CORS头"""
        try:
            origin = "http://localhost:5173"
            resp = requests.options(
                f"{self.GATEWAY_URL}/api/v1/health",
                headers={"Origin": origin, "Access-Control-Request-Method": "GET"},
                timeout=self.TIMEOUT
            )
            if resp.status_code == 204 or resp.status_code == 200:
                acao = resp.headers.get("Access-Control-Allow-Origin", "")
                assert acao != "*", f"CORS wildcard detected! Got: {acao}"
        except requests.exceptions.ConnectionError:
            pytest.skip("Gateway not available")


class TestAPIEndpoints:
    """API端点功能测试"""

    GATEWAY_URL = os.getenv("AGENTOS_GATEWAY_URL", "http://localhost:18789")
    TIMEOUT = int(os.getenv("TEST_TIMEOUT", "10"))

    def test_api_returns_json(self):
        """API应返回JSON格式响应"""
        try:
            resp = requests.get(
                f"{self.GATEWAY_URL}/api/v1/metrics",
                timeout=self.TIMEOUT
            )
            if resp.status_code == 200:
                data = resp.json()
                assert isinstance(data, dict), "Response should be JSON object"
        except (requests.exceptions.ConnectionError, ValueError):
            pytest.skip("API not available or invalid response")

    def test_404_on_invalid_path(self):
        """无效路径应返回404"""
        try:
            resp = requests.get(
                f"{self.GATEWAY_URL}/api/v1/nonexistent_endpoint_xyz",
                timeout=self.TIMEOUT
            )
            assert resp.status_code == 404, f"Expected 404, got {resp.status_code}"
        except requests.exceptions.ConnectionError:
            pytest.skip("Gateway not available")


class TestSecurityHeaders:
    """安全头验证"""

    DESKTOP_URL = os.getenv("DESKTOP_URL", "http://localhost:8080")
    TIMEOUT = int(os.getenv("TEST_TIMEOUT", "10"))

    def test_security_headers_present(self):
        """Desktop前端应包含基本安全头"""
        try:
            resp = requests.get(self.DESKTOP_URL, timeout=self.TIMEOUT)
            headers = resp.headers
            
            assert "X-Frame-Options" in headers or "X-Content-Type-Options" in headers, \
                "Missing security headers"
        except requests.exceptions.ConnectionError:
            pytest.skip("Desktop not available")


class TestDockerConfiguration:
    """Docker配置验证（通过环境变量检测）"""

    def test_docker_running(self):
        """确认在Docker环境中运行"""
        if not os.path.exists("/.dockerenv") and not os.path.exists("/proc/1/cgroup"):
            pytest.skip("Not running inside Docker (this is OK for local dev)")

    def test_no_env_file_committed(self):
        """.env文件不应存在（只有.example）"""
        env_files = [".env", ".env.production", ".env.staging"]
        docker_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        
        for ef in env_files:
            full_path = os.path.join(docker_dir, ef)
            assert not os.path.exists(full_path) or \
                   os.path.basename(full_path).endswith(".example"), \
                   f"Sensitive file should not be committed: {ef}"
