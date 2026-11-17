require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  test "should get home" do
    get root_url
    assert_response :success
  end

  test "navbar shows the metallic logo with a WebP source and fixed dimensions" do
    get root_url
    assert_select "nav.site-nav a.site-nav__brand[aria-label]" do
      assert_select "source[type='image/webp'][srcset*='logo-tr-autofix-nav']"
      assert_select "img.site-nav__logo[width='184'][height='112']"
    end
  end
end
