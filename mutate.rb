require 'parser/current'
require 'unparser'
require 'set'
require 'ruby_codex'
require 'pp'

Mongoid.load!("mongoid.yaml", :development)

class ASTNodes; include Mongoid::Document; end
class ASTStats; include Mongoid::Document; end

codex = Codex.new(ASTNodes,ASTStats)

code = IO.read(ARGV[0])

def walk_tree(ast, &block)
	if ast.is_a?(AST::Node)
		new_ast = yield ast
		new_ast.updated(nil, new_ast.children.map { |x| walk_tree(x, &block) })
	else
		ast
	end
end

def mutate(node_list)
  return [] if node_list.empty?
	choice = $base_transforms.keys.sample
	$base_transforms[choice].call(node_list)
end

$base_transforms = {
	# :delete => Proc.new do |node_list|
	# 	node_list.delete_at((0...node_list.size).to_a.sample)
	# 	node_list
	# end,
	:prim_swap => Proc.new do |node_list|
	  to_swap = rand node_list.size
	  swaps = {
      "int" => AST::Node.new(:int, [0]),
      "str" => AST::Node.new(:str, ["str"]),
      "float" => AST::Node.new(:float, [0.0]),
      "array" => AST::Node.new(:array, []),
      "hash" => AST::Node.new(:hash, [])
    }
    node_list.map.with_index do |n,i|
      if i == to_swap
        key = swaps.keys.select { |k| k != n.type.to_s }.sample
        swaps[key]
      else
        n
      end
    end
  end
  # :swap => Proc.new do |node_list|
  #   c1 = (0...node_list.size).to_a.sample
  #   c2 = (0...node_list.size).to_a.sample
  #   node_list[c1], node_list[c2] = node_list[c2], node_list[c1]
  #   node_list
  # end
}

$seen = Hash.new { |h,k| h[k] = [] }

$node_transforms = {
	"send" => [
		  Proc.new do |node, keys, values| 
		    primatives = ["str","int","float","array","hash"]
        all_prim = keys[:sig].all? { |x| primatives.include?(x) } && keys[:sig].size > 0
        if all_prim
		      { :change => true, :type => "arg_swap", 
		        :node => node.updated(nil, node.children.take(2) + mutate(node.children.drop(2)))} 
	      else
	        {:change => false, :node => node}
        end
		  end,
      Proc.new do |node, keys, values|
        func = node.children[1]
        funcs = $seen["send"].select { |x| x[:sig].size == node.children.drop(2).size }.map { |x| x[:func].to_sym }
        funcs = funcs.select { |x| x != func }
        funcs = funcs.select { |x| ![:+,:-,:[]=,:[],:*,:<<,:<,:>,:<=,:>=,:==,:>>].include?(x) } if node.children.first == nil
              if funcs.size > 0
                { :change => true, :type => "name_change",
                  :node => node.updated(nil, node.children.map.with_index { |x,i| i == 1 ? funcs.sample : x }) }
              else
                {:change => false, :node => node}
              end
            end
	],
  # "ident" => [
  #     Proc.new do |node, keys, values|
  #       idents = $seen["ident"].map { |x| x[:ident] }.select { |x| x != node.children.first }
  #       primatives = ["str","int","float","array","hash"]
  #       if idents.size > 0 && primatives.include?(values[:ident_type])
  #           { :change => true, 
  #             :type => "ident change",
  #             :node => node.updated(nil, node.children.map.with_index { |x,i| i == 0 ? idents.sample.to_sym : x }) 
  #           }
  #         else
  #           { :change => false,
  #             :node => node }
  #         end
  #       end
  #   ]
}

ast = Parser::CurrentRuby.parse(code)
mutations = 0
ast2 = walk_tree(ast) do |node|
  new_node = nil
  codex.nodes.each do |k,v|
    v.process_node(node, "_mutate_", "_mutate_") do |k,v| 
      $seen[k[:type]].push(k)
      try_mutate = $node_transforms[k[:type]].sample.call(node,k,v) if $node_transforms[k[:type]]
      new_node = nil
      if try_mutate && try_mutate[:change]
        mutations += 1
        new_node = try_mutate[:node]
        puts try_mutate[:type]
        puts "1).#{Unparser.unparse(new_node)}\n2).#{Unparser.unparse(node)}"
      end
    end
  end    
	new_node || node
end

puts "#{mutations.to_s} mutations on #{code.split("\n").size.to_s} lines"
# puts Unparser.unparse(ast2)

messages = []
codex.tree_walk(ast2) do |node|
  q = codex.is_unlikely(node)
  if q.size > 0
    print "#{node.loc.line.to_s}:" rescue "ERR:"
    puts q.map { |x| x[:message] }.join("\n") if q.size > 0
    messages.concat q
  end
end

puts "#{messages.count.to_s} warnings / #{mutations.to_s} mutations"
