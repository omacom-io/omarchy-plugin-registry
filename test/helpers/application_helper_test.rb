require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  include ApplicationHelper

  test "compact counters use the shared three-significant-digit format" do
    assert_equal %w[999 1k 1.23k 10k 12.3k 1M 1.23M],
      [ 999, 1_000, 1_234, 9_999, 12_345, 999_999, 1_234_567 ].map { |number| compact_number(number) }
  end

  test "compact byte sizes use B below the abbreviated unit range" do
    assert_equal [ "0 B", "1 B", "702 B", "1 KB", "1.07 KB", "1.5 KB", "12.1 KB", "1 MB" ],
      [ 0, 1, 702, 1024, 1100, 1536, 12_345, 1.megabyte ].map { |number| compact_byte_size(number) }
  end

  test "compact UTC timestamps use fixed month names and normalize offsets" do
    timestamp = Time.new(2026, 8, 28, 1, 5, 42, "+09:00")

    assert_equal "27 aug 26 · 16:05 UTC", compact_utc_timestamp(timestamp)
  end

  test "new plugin status uses the shared strict recency cutoff" do
    travel_to Time.zone.local(2026, 9, 2, 12, 0, 0) do
      cutoff = ApplicationHelper::CARD_RECENCY.ago
      plugin = Struct.new(:first_published_at)

      refute plugin_new?(plugin.new(cutoff - 1.second))
      refute plugin_new?(plugin.new(cutoff))
      assert plugin_new?(plugin.new(cutoff + 1.second))
    end
  end
end
