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
