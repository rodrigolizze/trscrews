require "test_helper"

class ScrewsControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get screws_url
    assert_response :success
  end

  test "should get show" do
    screw = screws(:one)
    get screw_url(screw)
    assert_response :success
  end

  # Regression guard: ApplicationHelper lost `include Pagy::Frontend` in ae52c30
  # (2025-09-12), so `pagy_bootstrap_nav` raised NoMethodError. The catalog view only
  # calls that helper when `@pagy.pages > 1`, which kept the 500 dormant for as long
  # as the catalog fit on a single page.
  test "renders pagination nav when the catalog spans more than one page" do
    fill_catalog_past_one_page

    get screws_url

    assert_response :success
    assert_select "ul.pagination"
  end

  test "renders the second page of the catalog" do
    fill_catalog_past_one_page

    get screws_url(page: 2)

    assert_response :success
    assert_select "ul.pagination"
  end

  # Regression guard: a `?page=` beyond the last page raised Pagy::OverflowError, and
  # Rails turns that into a 500. Reachable by anyone editing the URL, or by a crawler
  # following a stale pagination link after the catalog shrinks. The overflow extra
  # (:last_page) makes Pagy serve the last page instead of raising.
  test "serves the last page instead of raising when the requested page overflows" do
    fill_catalog_past_one_page
    last_page = (Screw.count / Pagy::DEFAULT[:limit].to_f).ceil

    get screws_url(page: 999)

    assert_response :success
    assert_select "ul.pagination"
    assert_select "li.page-item.active", text: last_page.to_s
  end

  private

  # Reads the limit from Pagy so the test keeps working if the page size changes.
  def fill_catalog_past_one_page
    missing = (Pagy::DEFAULT[:limit].to_i + 1) - Screw.count

    missing.times do |index|
      Screw.create!(
        description: "Parafuso de Teste de Paginação #{index}",
        thread: "M8-1,25",
        price: 10.00,
        stock: 5
      )
    end
  end
end
