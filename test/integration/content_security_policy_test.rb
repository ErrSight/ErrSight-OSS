require "test_helper"

class ContentSecurityPolicyTest < ActionDispatch::IntegrationTest
  # Brand fonts are self-hosted woff2 now, so the CSP no longer needs (and must
  # not advertise) the Google Fonts CDN. Guards the font-host removal.
  test "CSP allows fonts only from self/data, not the Google Fonts CDN" do
    get root_path
    csp = response.headers["Content-Security-Policy"].to_s
    assert_not csp.empty?, "expected a Content-Security-Policy response header"

    font_src = csp[/font-src([^;]*)/, 1].to_s
    assert_includes font_src, "'self'"
    assert_no_match(/fonts\.gstatic\.com/, csp)
    assert_no_match(/fonts\.googleapis\.com/, csp)
  end
end
