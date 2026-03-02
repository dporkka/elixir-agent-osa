defmodule OptimalSystemAgent.Signal.ClassifierWeightTest do
  @moduledoc """
  Edge case tests for the classifier's weight calculation and deterministic behavior.
  Supplements the existing classifier_test.exs which covers mode/genre/type/format.
  """
  use ExUnit.Case, async: true

  alias OptimalSystemAgent.Signal.Classifier

  # ---------------------------------------------------------------------------
  # Weight calculation boundaries
  # ---------------------------------------------------------------------------

  describe "calculate_weight/1 boundaries" do
    test "empty string has base weight 0.5" do
      # No bonuses, no penalties
      weight = Classifier.calculate_weight("")
      assert weight == 0.5
    end

    test "weight is never below 0.0" do
      # Greeting-only messages get noise penalty
      weight = Classifier.calculate_weight("hello")
      assert weight >= 0.0
    end

    test "weight is never above 1.0" do
      # Max everything: long, question, urgent
      long_urgent = String.duplicate("urgent critical ", 100) <> "?"
      weight = Classifier.calculate_weight(long_urgent)
      assert weight <= 1.0
    end

    test "question mark adds bonus" do
      without = Classifier.calculate_weight("tell me about authentication")
      with_q = Classifier.calculate_weight("tell me about authentication?")
      assert with_q > without
    end

    test "urgency words add bonus" do
      normal = Classifier.calculate_weight("fix the bug")
      urgent = Classifier.calculate_weight("fix the bug urgent")
      assert urgent > normal
    end

    test "all urgency keywords work" do
      for word <- ~w(urgent asap critical emergency immediately) do
        weight = Classifier.calculate_weight("please help #{word}")
        assert weight > 0.5, "Expected '#{word}' to increase weight above 0.5, got #{weight}"
      end
    end

    test "'now' as urgency keyword works" do
      weight = Classifier.calculate_weight("do it now")
      assert weight > 0.5
    end

    test "greeting words apply noise penalty" do
      for word <- ~w(hello thanks lol haha) do
        weight = Classifier.calculate_weight(word)
        assert weight < 0.5, "Expected '#{word}' to decrease weight below 0.5, got #{weight}"
      end
    end

    test "short greeting words apply noise penalty" do
      for word <- ~w(hi ok hey sure) do
        weight = Classifier.calculate_weight(word)
        assert weight < 0.5, "Expected '#{word}' to decrease weight below 0.5, got #{weight}"
      end
    end

    test "longer messages get length bonus" do
      short = Classifier.calculate_weight("fix bug")
      long = Classifier.calculate_weight(String.duplicate("detailed explanation of the problem ", 20))
      assert long > short
    end

    test "length bonus caps at 0.2" do
      # 500+ chars should cap the length bonus
      medium = String.duplicate("word ", 100)  # 500 chars
      very_long = String.duplicate("word ", 1000)  # 5000 chars

      w_medium = Classifier.calculate_weight(medium)
      w_long = Classifier.calculate_weight(very_long)

      # Both should be capped — difference should be minimal
      assert abs(w_medium - w_long) < 0.05
    end
  end

  # ---------------------------------------------------------------------------
  # Deterministic consistency
  # ---------------------------------------------------------------------------

  describe "deterministic behavior" do
    test "same input always produces same classification" do
      msg = "build a new REST API for user authentication"

      results = for _ <- 1..10, do: Classifier.classify_fast(msg, :cli)

      # All results should be identical
      first = hd(results)
      for result <- results do
        assert result.mode == first.mode
        assert result.genre == first.genre
        assert result.type == first.type
        assert result.format == first.format
        assert result.weight == first.weight
      end
    end

    test "classification includes all 5 tuple fields" do
      result = Classifier.classify_fast("test message", :cli)

      assert result.mode in [:execute, :assist, :analyze, :build, :maintain]
      assert result.genre in [:direct, :inform, :commit, :decide, :express]
      assert is_binary(result.type)
      assert result.format in [:message, :document, :notification, :command, :transcript]
      assert is_float(result.weight)
      assert result.weight >= 0.0 and result.weight <= 1.0
    end

    test "timestamp is set" do
      result = Classifier.classify_fast("test", :cli)
      assert %DateTime{} = result.timestamp
    end

    test "raw message is preserved" do
      msg = "  some message with spaces  "
      result = Classifier.classify_fast(msg, :cli)
      assert result.raw == msg
    end

    test "channel is preserved" do
      result = Classifier.classify_fast("test", :telegram)
      assert result.channel == :telegram
    end

    test "confidence is :low (deterministic only)" do
      result = Classifier.classify_fast("test", :cli)
      assert result.confidence == :low
    end
  end

  # ---------------------------------------------------------------------------
  # Channel-specific format classification
  # ---------------------------------------------------------------------------

  describe "format classification by channel" do
    test "cli maps to :command" do
      assert Classifier.classify_fast("test", :cli).format == :command
    end

    test "telegram maps to :message" do
      assert Classifier.classify_fast("test", :telegram).format == :message
    end

    test "discord maps to :message" do
      assert Classifier.classify_fast("test", :discord).format == :message
    end

    test "slack maps to :message" do
      assert Classifier.classify_fast("test", :slack).format == :message
    end

    test "whatsapp maps to :message" do
      assert Classifier.classify_fast("test", :whatsapp).format == :message
    end

    test "webhook maps to :notification" do
      assert Classifier.classify_fast("test", :webhook).format == :notification
    end

    test "filesystem maps to :document" do
      assert Classifier.classify_fast("test", :filesystem).format == :document
    end

    test "unknown channel maps to :message" do
      assert Classifier.classify_fast("test", :unknown_channel).format == :message
    end
  end

  # ---------------------------------------------------------------------------
  # Mode classification edge cases
  # ---------------------------------------------------------------------------

  describe "mode classification" do
    test "build mode triggers" do
      for word <- ~w(build create generate make scaffold design) do
        result = Classifier.classify_fast("please #{word} something", :cli)
        assert result.mode == :build, "Expected '#{word}' to trigger :build mode, got #{result.mode}"
      end
    end

    test "execute mode triggers" do
      for word <- ~w(run execute trigger sync send) do
        result = Classifier.classify_fast("#{word} the migration", :cli)
        assert result.mode == :execute, "Expected '#{word}' to trigger :execute mode, got #{result.mode}"
      end
    end

    test "analyze mode triggers" do
      for word <- ~w(analyze report dashboard metrics) do
        result = Classifier.classify_fast("#{word} the performance", :cli)
        assert result.mode == :analyze, "Expected '#{word}' to trigger :analyze mode, got #{result.mode}"
      end
    end

    test "maintain mode triggers" do
      for word <- ~w(update upgrade migrate fix backup restore) do
        result = Classifier.classify_fast("#{word} the system", :cli)
        assert result.mode == :maintain, "Expected '#{word}' to trigger :maintain mode, got #{result.mode}"
      end
    end

    test "defaults to :assist for neutral messages" do
      result = Classifier.classify_fast("tell me about elixir", :cli)
      assert result.mode == :assist
    end
  end
end
