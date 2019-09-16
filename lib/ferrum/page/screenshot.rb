# frozen_string_literal: true

module Ferrum
  class Page
    module Screenshot
      def screenshot(**opts)
        path, encoding = common_options(**opts)
        options = screenshot_options(path, **opts)
        data = command("Page.captureScreenshot", **options).fetch("data")
        return data if encoding == :base64
        save_file(path, data)
      end

      def pdf(**opts)
        path, encoding = common_options(**opts)
        options = pdf_options(**opts)
        data = command("Page.printToPDF", **options).fetch("data")
        return data if encoding == :base64
        save_file(path, data)
      end

      private

      def save_file(path, data)
        bin = Base64.decode64(data)
        return bin unless path
        File.open(path.to_s, "wb") { |f| f.write(bin) }
      end

      def common_options(encoding: :base64, path: nil, **_)
        encoding = encoding.to_sym
        encoding = :binary if path
        [path, encoding]
      end

      def pdf_options(landscape: false, paper_width: 8.5, paper_height: 11, scale: 1.0, **opts)
        options = {}
        options[:landscape] = landscape
        options[:paperWidth] = paper_width.to_f
        options[:paperHeight] = paper_height.to_f
        options[:scale] = scale.to_f
        options.merge(opts)
      end

      def screenshot_options(path = nil, format: nil, scale: 1.0, **opts)
        options = {}

        format ||= path ? File.extname(path).delete(".") : "png"
        format = "jpeg" if format == "jpg"
        raise "Not supported options `:format` #{format}. jpeg | png" if format !~ /jpeg|png/i
        options.merge!(format: format)

        options.merge!(quality: opts[:quality] ? opts[:quality] : 75) if format == "jpeg"

        if !!opts[:full] && opts[:selector]
          warn "Ignoring :selector in #screenshot since full: true was given at #{caller(1..1).first}"
        end

        if !!opts[:full]
          width, height = evaluate("[document.documentElement.offsetWidth, document.documentElement.offsetHeight]")
          options.merge!(clip: { x: 0, y: 0, width: width, height: height, scale: scale }) if width > 0 && height > 0
        elsif opts[:selector]
          rect = evaluate("document.querySelector('#{opts[:selector]}').getBoundingClientRect()")
          options.merge!(clip: { x: rect["x"], y: rect["y"], width: rect["width"], height: rect["height"], scale: scale })
        end

        if scale != 1.0
          if !options[:clip]
            width, height = evaluate("[document.documentElement.clientWidth, document.documentElement.clientHeight]")
            options[:clip] = { x: 0, y: 0, width: width, height: height }
          end

          options[:clip].merge!(scale: scale)
        end

        options
      end
    end
  end
end
