class Hash
  def in_groups_of(count, allow_nil = false)
    h = self
    h.map{|k, v| {:"#{k}" => v} }.flatten.in_groups_of(count , allow_nil).map{|group| Hash[group.map{|e| [e.keys.first, e.first.second] }] }
  end

  def in_groups(count, allow_nil = false, &block)
    h = self
    in_groups_of((h.keys.count.to_f / count).ceil, allow_nil, &block)
  end
end