require "test_helper"

class TerminalSubpagesTest < ActionDispatch::IntegrationTest
  test "governance uses the shared terminal shell without hiding its public controls" do
    get governance_path

    assert_response :success
    assert_select "article.terminal-window.terminal-window--ansi[aria-labelledby='governance-title']", 1
    assert_select ".terminal-window__titlebar", text: /Governance.*learn\.governance.*read only/m
    assert_select ".terminal-window__prompt[aria-label='Command: omarchy registry powers']", 1 do
      assert_select "i", count: 0
    end
    assert_select "nav.terminal-window__index--tree[aria-label='Governance sections'][data-controller='terminal-tree']" do
      assert_select ".terminal-window__tree a[data-terminal-tree-target='link'][data-action='terminal-tree#select']", 3
      assert_select "a.is-active[aria-current='location'][href='#powers']", text: /powers/, count: 1
    end
    assert_select "#powers .terminal-actions li", 4
    assert_equal %w[[1] [2] [3] [4]], css_select("#powers .terminal-actions i").map { |node| node.text.strip }
    assert_select "a[href='mailto:registry@omarchy.org']", text: "registry@omarchy.org"
    assert_select "a[href=?]", audit_log_path, text: /public audit log/
  end

  test "publishing keeps every operational command and progressive sign-in link" do
    get publishing_path

    assert_response :success
    assert_select "article.terminal-window.terminal-window--ansi[aria-labelledby='publishing-title']", 1
    assert_select ".terminal-window__titlebar", text: /Publishing guide.*publish\.guide.*read only/m
    assert_select ".terminal-window__prompt[aria-label='Command: omarchy plugin publish --help']", 1 do
      assert_select "i", count: 0
    end
    assert_select "nav.terminal-window__index--tree[aria-label='Publishing guide sections'][data-controller='terminal-tree']" do
      assert_select ".terminal-window__tree" do
        assert_select "a[data-terminal-tree-target='link'][data-action='terminal-tree#select']", 6
        assert_select "a.is-active[aria-current='location'][href='#quick-start']", text: /quick start/, count: 1
      end
    end
    assert_equal %w[[1] [2] [3]], css_select(".terminal-step__number").map { |node| node.text.strip }
    assert_select "pre", text: /omarchy plugin new weather/
    assert_select "pre", text: /omarchy plugin publish.*curl -X POST/m
    assert_select "a[href=?]", new_session_path, text: "Sign in"
    assert_select "#rules .terminal-rules li", 4
    assert_select "#trusted", text: /OIDC.*no stored secret.*exact commit/m
  end

  test "audit renders truthful public events and keeps its feed discoverable" do
    publisher = Publisher.create!(name: "acme", kind: :org)
    AuditEvent.record!(action: "namespace.claimed", subject: publisher,
      metadata: { "publisher" => "acme" }, public: true)

    get audit_log_path

    assert_response :success
    assert_select "article.terminal-window[aria-labelledby='audit-title']", 1
    assert_select ".terminal-window__titlebar", text: /Audit log.*audit\.log.*public/m
    assert_select ".terminal-window__prompt[aria-label='Command: omarchy registry audit --public']", 1 do
      assert_select "i[aria-hidden='true']", count: 1
    end
    assert_select "nav[aria-label='Audit log sections'] a[href=?]", feed_path, text: /feed/
    assert_select "a.nav__section--active[aria-current='location'][href=?]", governance_path, text: "governance"
    assert_select ".terminal-audit li", 1 do
      assert_select "time[datetime]", 1
      assert_select "b", text: "namespace.claimed"
      assert_select "span", text: "publisher: acme"
    end
  end

  test "sign-in shell preserves email and passkey authentication contracts" do
    get new_session_path

    assert_response :success
    assert_select "article.terminal-window[aria-labelledby='sign-in-title']", 1
    assert_select ".terminal-window__titlebar", text: /Sign in.*session\.new.*passkey ready/m
    assert_select ".terminal-window__prompt[aria-label='Command: omarchy auth request-code']", 1 do
      assert_select "i", count: 0
    end
    assert_select ".terminal-window__main[data-controller='webauthn']" do
      assert_select "form#email-code[action=?][method='post']", session_path do
        assert_select "input#email_address[type='email'][name='email_address'][required][autofocus][autocomplete='email']", 1
        assert_select "button[type='submit']", text: "Email me a code", count: 1
        assert_select "#passkey button[type='button'][data-action='webauthn#authenticate']", text: "Sign in with a passkey", count: 1
      end
      assert_select ".terminal-auth-status[role='status'][aria-live='polite'][aria-atomic='true']" do
        assert_select ".terminal-auth-status__error b", text: "[ error ]"
        assert_select ".terminal-auth-status__error [data-webauthn-target='error']:empty", 1
      end
    end
  end

  test "signed-out primary navigation uses the concise sign-in label" do
    get root_path

    assert_select "a.nav__account[href=?]", new_session_path, text: "sign-in →", count: 1
    assert_select "a.nav__account", text: /auth\//, count: 0

    get new_session_path
    assert_select "a.nav__account[aria-current='page'][href=?]", new_session_path, text: "sign-in →", count: 1
  end
end
