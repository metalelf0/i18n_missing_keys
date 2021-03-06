# Fetched from: http://github.com/koppen/i18n_missing_keys.git

namespace :i18n do
  desc "Find and list translation keys that do not exist in all locales"
  task :missing_keys => :environment do
    backend = I18n.backend.kind_of?(I18n::Backend::Chain) ? 
              I18n.backend.backends.find { |b| b.kind_of?(I18n::Backend::Simple) } :
              I18n.backend

    finder = MissingKeysFinder.new(backend)
    finder.find_missing_keys
  end
end


class MissingKeysFinder

  SHOULD_SHOW_BLANK_TRANSLATIONS = true

  def initialize(backend)
    @backend = backend
    @rails_views = Rails.configuration.paths.all_paths.first.children["views"].paths.first + "/*"
    self.load_config
    self.load_translations
    self.lookup_keys_in_views
  end

  # Returns an array with all keys from all locales
  def all_keys
    return @all_keys unless @all_keys.nil?
    keys_from_backend = @backend.send(:translations).collect do |check_locale, translations|
      collect_keys([], translations).sort
    end.flatten.uniq
    keys_from_file = File.open("/tmp/missing_keys").readlines.reject { |e| e.blank? }.map(&:strip)
    return (@all_keys = (keys_from_backend + keys_from_file).flatten.uniq.sort)
  end

  def lookup_keys_in_views
    system('echo > /tmp/missing_keys')
    system('grep -iro \'t(".*")\' ' + @rails_views + ' | cut -d "\"" -f 2 | sort | uniq >> /tmp/missing_keys')
    system('grep -iro "t \'.*\'" ' + @rails_views + ' | cut -d ":" -f 2 | cut -d " " -f 2 | sort | uniq | sed "s/\'//g" >> /tmp/missing_keys')
  end


  def find_missing_keys
    output_available_locales
    output_unique_key_stats(all_keys)

    missing_keys = {}
    all_keys.each do |key|

      I18n.available_locales.each do |locale|

        skip = false
        ls = locale.to_s
        if !@yaml[ls].nil?
          @yaml[ls].each do |re|
            if key.match(re)
              skip = true
              break
            end
          end
        end

        if !key_exists?(key, locale) && skip == false
          if missing_keys[key]
            missing_keys[key] << locale
          else
            missing_keys[key] = [locale]
          end
        end
      end
    end

    output_missing_keys(missing_keys)
    return missing_keys
  end

  def output_available_locales
    puts "#{I18n.available_locales.size} #{I18n.available_locales.size == 1 ? 'locale' : 'locales'} available: #{I18n.available_locales.join(', ')}"
  end

  def output_missing_keys(missing_keys)
    puts "#{missing_keys.size} #{missing_keys.size == 1 ? 'key is missing' : 'keys are missing'} from one or more locales:"
    missing_keys.keys.sort.each do |key|
      puts "'#{key}': Missing from #{missing_keys[key].collect(&:inspect).join(', ')}"
    end
  end

  def output_unique_key_stats(keys)
    number_of_keys = keys.size
    puts "#{number_of_keys} #{number_of_keys == 1 ? 'unique key' : 'unique keys'} found."
  end

  def collect_keys(scope, translations)
    full_keys = []
    translations.to_a.each do |key, translations|
      next if translations.nil?

      new_scope = scope.dup << key
      if translations.is_a?(Hash)
        full_keys += collect_keys(new_scope, translations)
      else
        full_keys << new_scope.join('.')
      end
    end
    return full_keys
  end

  # Returns true if key exists in the given locale
  def key_exists?(key, locale)
    I18n.locale = locale
    value = I18n.translate(key, :raise => true)
    return false if (value.blank? && SHOULD_SHOW_BLANK_TRANSLATIONS)
    return true
  rescue I18n::MissingInterpolationArgument
    return true
  rescue I18n::MissingTranslationData
    return false
  end

  def load_translations
    # Make sure we’ve loaded the translations
    @backend.send(:init_translations)
  end

  def load_config
    @yaml = {}
    begin
      @yaml = YAML.load_file(File.join(Rails.root, 'config', 'ignore_missing_keys.yml'))
    rescue => e
      STDERR.puts "No ignore_missing_keys.yml config file."
    end

  end

end
