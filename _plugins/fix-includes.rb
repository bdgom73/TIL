class Jekyll::Tags::IncludeTag
  def render(context)
    if @params.strip.start_with?("cached ")
      @params.sub!("cached ", "")
    end
    super
  end
end