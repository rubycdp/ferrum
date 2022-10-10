# frozen_string_literal: true

module Ferrum
  class Browser
    describe Binary do
      let(:tmp_bin) { "#{PROJECT_ROOT}/spec/tmp/bin" }
      let(:bin1) { File.join(tmp_bin, "bin1") }
      let(:bin1_exe) { File.join(tmp_bin, "bin1.exe") }
      let(:bin2_no_x) { File.join(tmp_bin, "/bin2") }
      let(:bin3) { File.join(tmp_bin, "/bin3") }
      let(:bin4_exe) { File.join(tmp_bin, "/bin4.exe") }

      before do
        FileUtils.mkdir_p(tmp_bin)
        FileUtils.touch([bin1, bin1_exe, bin2_no_x, bin3, bin4_exe])
        FileUtils.chmod("u=rwx,go=rx", bin1)
        FileUtils.chmod("u=rwx,go=rx", bin1_exe)
        FileUtils.chmod("u=rw,go=r", bin2_no_x)
        FileUtils.chmod("u=rwx,go=rx", bin3)
        FileUtils.chmod("u=rwx,go=rx", bin4_exe)

        @original_env_path = ENV.fetch("PATH", nil)
        @original_env_pathext = ENV.fetch("PATHEXT", nil)
        ENV["PATH"] = "#{tmp_bin}#{File::PATH_SEPARATOR}#{@original_env_path}"
      end

      after do
        FileUtils.rm_rf(tmp_bin)
        ENV["PATH"] = @original_env_path
        ENV["PATHEXT"] = @original_env_pathext
      end

      describe "#find" do
        it "finds one binary" do
          expect(Binary.find("bin1")).to eq(bin1)
        end

        it "finds first binary when list is passed" do
          expect(Binary.find(%w[bin1 bin3])).to eq(bin1)
        end

        it "finds binary with PATHEXT" do
          ENV["PATHEXT"] = ".com;.exe"

          expect(Binary.find(%w[bin4])).to eq(bin4_exe)
        end

        it "finds binary with absolute path" do
          expect(Binary.find(bin4_exe)).to eq(bin4_exe)
        end

        it "finds binary without ext" do
          ENV["PATHEXT"] = ".com;.exe"

          expect(Binary.find("bin1")).to eq(bin1_exe)
          FileUtils.rm_rf(bin1_exe)
          expect(Binary.find("bin1")).to eq(bin1)
        end

        it "raises an error" do
          ENV["PATH"] = ""

          expect { Binary.find(%w[bin1]) }.to raise_error(Ferrum::EmptyPathError)
        end
      end

      describe "#all" do
        it "finds one binary" do
          expect(Binary.all("bin1")).to eq([bin1])
        end

        it "finds multiple binaries with ext" do
          ENV["PATHEXT"] = ".com;.exe"

          expect(Binary.all("bin1")).to eq([bin1_exe, bin1])
        end

        it "finds all binary when list passed" do
          expect(Binary.all(%w[bin1 bin3])).to eq([bin1, bin3])
        end

        it "finds binary with PATHEXT" do
          ENV["PATHEXT"] = ".com;.exe"

          expect(Binary.all(%w[bin4])).to eq([bin4_exe])
        end

        it "raises an error" do
          ENV["PATH"] = ""

          expect { Binary.all(%w[bin1]) }.to raise_error(Ferrum::EmptyPathError)
        end
      end

      describe "#lazy_find" do
        it "works lazily" do
          enum = Binary.lazy_find(%w[ls which none])

          expect(enum.instance_of?(Enumerator::Lazy)).to be_truthy
        end
      end
    end
  end
end
