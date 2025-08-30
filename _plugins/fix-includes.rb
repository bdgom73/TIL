# _plugins/fix-includes.rb

class Jekyll::Tags::IncludeTag
  def render(context)
    # Hack to make the include_cached Liquid tag work with GitHub Pages
    # Source: https://github.com/mmistakes/minimal-mistakes/issues/3041
    if @params.strip.start_with?("cached ")
      @params.sub!("cached ", "")
    end
    super
  end
end