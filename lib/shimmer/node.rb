# A representation of a single DOM node
#
# Our current implementation depends on Ruby-land Nokogiri parsing for reading
# attributes, then shifting to a DevTools protocol-based implementation for
# manipulating properties.
module Capybara
  module Shimmer
    class Node < Capybara::RackTest::Node
      attr_reader :devtools_node_id, :devtools_backend_node_id, :devtools_remote_object_id, :logger

      def initialize(driver,
                     native,
                     devtools_node_id:,
                     devtools_backend_node_id:,
                     devtools_remote_object_id:)
        super(driver, native)
        @devtools_node_id = devtools_node_id
        @devtools_backend_node_id = devtools_backend_node_id
        @devtools_remote_object_id = devtools_remote_object_id
        @logger = Logger.new(STDOUT)
      end

      def value
        javascript_bridge.evaluate_js("function() { return this.value }")
      end

      def all_text
        text = javascript_bridge.evaluate_js("function() { return this.textContent }")
        Capybara::Helpers.normalize_whitespace(text)
      end

      def visible_text
        text = visible? ? inner_text : ""
        Capybara::Helpers.normalize_whitespace(text)
      end

      def click
        scroll_into_view_if_needed!
        maybe_block_until_network_request_finishes! do
          mouse_driver.click(self)
        end
      end

      def set(value)
        scroll_into_view_if_needed!
        if input_field?
          select!
          keyboard_driver.type(value)
        else
          javascript_bridge.evaluate_js("function() { this.value = '#{value}'; }")
        end
      end

      def send_keys(value)
        scroll_into_view_if_needed!
        select!
        keyboard_driver.type_raw(value)
      end

      def focus!
        javascript_bridge.evaluate_js("function() { return this.focus() }")
      end

      def select!
        javascript_bridge.evaluate_js("function() { return this.select() }")
      end

      def hover
        scroll_into_view_if_needed!
        mouse_driver.move_to(self)
      end

      def center_coordinates
        x = bounding_box.x + (bounding_box.width / 2)
        y = bounding_box.y + (bounding_box.height / 2)
        OpenStruct.new(x: x, y: y)
      end

      def select_option
        javascript_bridge.evaluate_js("
          function() {
            this.dispatchEvent(new Event('input', { 'bubbles': true }));
            this.dispatchEvent(new Event('change', { 'bubbles': true }));
            this.selected = true;
          }
        ")
      end

      def html
        javascript_bridge.evaluate_js("function() { return this.innerHTML }")
      end

      def find_css(query)
        Capybara::Shimmer::Finder.new(browser).scoped_find_css(query, scope: self)
      end

      def find_xpath(query)
        Capybara::Shimmer::Finder.new(browser).scoped_find_xpath(query, scope: self)
      end

      def visible?
        javascript_bridge.evaluate_js(Capybara::Shimmer::JavascriptExpressions::NODE_VISIBLE)
      end

      private

      def inner_text
        javascript_bridge.evaluate_js(Capybara::Shimmer::JavascriptExpressions::INNER_TEXT)
      end

      def maybe_block_until_network_request_finishes!(&block)
        unless browser.anticipate_event("Network.requestWillBeSent", &block)
          browser.wait_for("Network.requestWillBeSent", timeout: 0.1)
        end
        browser.wait_for("Network.loadingFinished", timeout: 5)
      rescue Timeout::Error => _e
        logger.debug "No network event processed - continuing."
      end

      def box_model
        @box_model ||= browser.send_cmd("DOM.getBoxModel", backendNodeId: devtools_backend_node_id).model
      end

      def bounding_box
        quad = box_model.border
        x = [quad[0], quad[2], quad[4], quad[6]].min
        y = [quad[1], quad[3], quad[5], quad[7]].min
        width = [quad[0], quad[2], quad[4], quad[6]].max - x
        height = [quad[1], quad[3], quad[5], quad[7]].max - y

        OpenStruct.new(x: x, y: y, width: width, height: height)
      end

      def scroll_into_view_if_needed!
        javascript_bridge.evaluate_js("function() { return this.scrollIntoViewIfNeeded() }")
      end

      def javascript_bridge
        @javascript_bridge ||= JavascriptBridge.new(browser, devtools_remote_object_id: devtools_remote_object_id)
      end

      def mouse_driver
        @mouse_driver ||= MouseDriver.new(browser)
      end

      def keyboard_driver
        @keyboard_driver ||= KeyboardDriver.new(browser)
      end

      def browser
        driver.browser
      end
    end
  end
end
