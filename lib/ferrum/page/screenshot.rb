# frozen_string_literal: true

module Ferrum
  class Page
    module Screenshot

      PAPEP_FORMATS = {
        letter:   { width:  8.50, height: 11.00 },
        legal:    { width:  8.50, height: 14.00 },
        tabloid:  { width: 11.00, height: 17.00 },
        ledger:   { width: 17.00, height: 11.00 },
        A0:       { width: 33.10, height: 46.80 },
        A1:       { width: 23.40, height: 33.10 },
        A2:       { width: 16.54, height: 23.40 },
        A3:       { width: 11.70, height: 16.54 },
        A4:       { width:  8.27, height: 11.70 },
        A5:       { width:  5.83, height:  8.27 },
        A6:       { width:  4.13, height:  5.83 },
      };

      def screenshot(**opts)
        path, encoding = common_options(**opts)
        options = screenshot_options(path, **opts)
        data = fetch_screenshot_capture(options, fullscreen: opts[:full])
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

      def viewport_size
        evaluate <<~JS
          [window.innerWidth, window.innerHeight]
        JS
      end

      def document_size
        evaluate <<~JS
          [document.documentElement.offsetWidth,
           document.documentElement.offsetHeight]
        JS
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

      def pdf_options(**opts)
        options = default_pdf_options
        if format = opts.delete(:format)
          raise "you can not specify format and dimensions" if opts[:paper_width] || opts[:paper_height]
          if dimension = PAPEP_FORMATS[format]
            options[:paper_width] = dimension[:width]
            options[:paper_height] = dimension[:height]
          else
            raise "Could not find format #{format}, existing once are #{PAPER_FORMATS.keys.join(", ")}"
          end
        end
        Ferrum::convert_option_hash options.merge(opts)
      end

      def default_pdf_options
        {
          landscape: false,
          paper_width: 8.5,
          paper_height: 11,
          scale: 1.0
        }
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
          width, height = document_size
          options.merge!(clip: { x: 0, y: 0, width: width, height: height, scale: scale }) if width > 0 && height > 0
        elsif opts[:selector]
          options.merge!(clip: get_bounding_rect(opts[:selector]).merge(scale: scale))
        end

        if scale != 1.0
          if !options[:clip]
            width, height = viewport_size
            options[:clip] = { x: 0, y: 0, width: width, height: height }
          end

          options[:clip].merge!(scale: scale)
        end

        options
      end

      def get_bounding_rect(selector)
        rect = evaluate_async(%Q(
          const rect = document
                         .querySelector('#{selector}')
                         .getBoundingClientRect();
          const {x, y, width, height} = rect;
          arguments[0]([x, y, width, height])
        ), timeout)

        { x: rect[0], y: rect[1], width: rect[2], height: rect[3] }
      end

      def fetch_screenshot_capture(options, fullscreen: false)
        current_viewport_size_values = viewport_size.dup
        resize(fullscreen: true) if fullscreen
        data = command("Page.captureScreenshot", **options).fetch("data")
        if fullscreen
          width, height = current_viewport_size_values
          resize(width: width, height: height)
        end
        data
      end
    end
  end
end
