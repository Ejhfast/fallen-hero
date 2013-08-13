require 'parser/current'
require 'unparser'
require 'set'
require 'codex'
require 'pp'

codex = Codex.new(nil,nil)

code = """
def add(x,y)
	x + y
end
add 2, 3
"""

def walk_tree(ast, &block)
	if ast.is_a?(AST::Node)
		ast = yield ast
		ast.updated(nil, ast.children.map { |x| walk_tree(x, &block) })
	else
		ast
	end
end

def mutate(node_list)
	choice = $base_transforms.keys.sample
	$base_transforms[choice].call(node_list)
end

$base_transforms = {
	# :delete => Proc.new do |node_list|
	# 	node_list.delete_at((0...node_list.size).to_a.sample)
	# 	node_list
	# end,
	:swap => Proc.new do |node_list|
		c1 = (0...node_list.size).to_a.sample
		c2 = (0...node_list.size).to_a.sample
		node_list[c1], node_list[c2] = node_list[c2], node_list[c1]
		node_list
	end
}

$seen = Hash.new { h[k] = Set.new }

$node_transforms = {
	:func_call => {
		:match => Proc.new { |x| x.type == :send },
		:transform => Proc.new { |node| node.updated(nil, node.children.take(2) + mutate(node.children.drop(2))) }
	}
}

ast = Parser::CurrentRuby.parse(code)

ast2 = walk_tree(ast) do |node|
	$node_transforms.each do |k,v|
		if v[:match].call(node)
			node = v[:transform].call(node) rescue ""
		end
	end
	node
end

puts Unparser.unparse(ast2)
