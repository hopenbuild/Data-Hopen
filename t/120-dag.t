#!perl
# 120-dag.t: basic tests of Data::Hopen::G::DAG
use rlib 'lib';
use HopenTest;
use Test::Deep::NoTest;     # NoTest since I am using eq_deeply directly
use Test::Fatal;

use Data::Hopen qw(:v);
use Data::Hopen::G::DAG;
use Data::Hopen::G::Node;
use Data::Hopen::G::NoOp;
use Scalar::Util qw(refaddr);

diag "Testing Data::Hopen::G::DAG from $INC{'Data/Hopen/G/DAG.pm'}";

my $dag = Data::Hopen::G::DAG->new(name=>'foo');
isa_ok($dag, 'Data::Hopen::G::DAG');
is($dag->name, 'foo', 'Name was set by constructor');
$dag->name('bar');
is($dag->name, 'bar', 'Name was set by accessor');

ok($dag->_graph, 'DAG has a _graph');
ok($dag->_final, 'DAG has a _final');
ok($dag->empty, 'DAG is initially empty');
cmp_ok($dag->_graph->vertices, '==', 1, 'DAG initially has 1 vertex');

my @goals;
foreach my $goalname (qw(all clean)) {
    my $g1 = $dag->goal($goalname);
    push @goals, $g1;
    isa_ok($g1, 'Data::Hopen::G::Goal', 'DAG::goal()');
    is($g1->name, $goalname, 'DAG::goal() sets goal name');
    ok($dag->_graph->has_edge($g1, $dag->_final), 'DAG::goal() adds goal->final edge');
}

ok(!$dag->empty, 'DAG is not empty after adding goals');
cmp_ok($dag->_graph->vertices, '>', 1, 'DAG has >1 vertex after adding goals');
ok($dag->default_goal, 'DAG::goal() sets default_goal');
is($dag->default_goal->name, 'all', 'First call to DAG::goal() sets default goal name');
cmp_ok(refaddr($dag->goal('all')), '==', refaddr($dag->default_goal),
    'default_goal is accessible by name');

# add()
my $name = 'some operation';
my $op = Data::Hopen::G::NoOp->new(name => $name);
{
    local $VERBOSE = 3;     # for coverage of the hlog
    $dag->add($op);
}
ok($dag->_graph->has_vertex($op), 'add() adds node');
cmp_ok($dag->_graph->get_vertex_count($op), '==', 1, 'add() initial count 1');
$dag->add($op);
cmp_ok($dag->_graph->get_vertex_count($op), '==', 1, 'add() count still 1');

like( exception {$dag->goal($name)}, qr/same name.+non-goal/,
    'goal() rejects goal with the same name as existing node');

ok(!defined($dag->node_by_name('Nonexistent node!')), 'node_by_name returns undef for nonexistent node');
my $got_op = $dag->node_by_name($name);
ok($got_op, 'node_by_name returned a value');
cmp_ok(refaddr($got_op), '==', refaddr($op), 'node_by_name returned the correct value');

my $name2 = 'different';
my $op2 = Data::Hopen::G::NoOp->new(name => $name2);
$dag->add($op2);
my $got_op2 = $dag->node_by_name($name2);
cmp_ok(refaddr($got_op2), '==', refaddr($op2), 'node_by_name returned the correct value for a different name');

# add a duplicate
my $vcount = $dag->_graph->vertices;
my $op3 = $dag->add($op);
cmp_ok(refaddr($op3), '==', refaddr($op), 'add(same name) returned the existing node');
cmp_ok($dag->_graph->vertices, '==', $vcount, 'add(existing) did not change vertex count');

# add duplicate name
my $op4 = Data::Hopen::G::NoOp->new(name => $name);
my $op5 = $dag->add($op4);
cmp_ok(refaddr($op5), '==', refaddr($op), 'add(same name) returned the existing node');
cmp_ok($dag->_graph->vertices, '==', $vcount, 'add(same name) did not change vertex count');

# init()

our @results;   # lexical visible in the following package
package MY::AppendOp {
    use parent 'Data::Hopen::G::Node';
    use Class::Tiny;
    sub _run {
        push @results, (shift)->name;
        return {};  # Must return a hashref
    }
} #MY::AppendOp

# Make a dummy DAG so it will run - what we care about is the init graph
$dag = Data::Hopen::G::DAG->new(name=>'dag_with_init');
my $goal = $dag->goal('some goal');
{
    local $VERBOSE = 1;     # for coverage
    $dag->connect(Data::Hopen::G::NoOp->new, $goal);
}

my @ops = map { MY::AppendOp->new(name => "$_") } qw(1 2 3);
cmp_ok($dag->_init_graph->vertices, '==', 1, 'Init graph initially has 1 vertex');
$dag->init($ops[0]);
cmp_ok($dag->_init_graph->vertices, '==', 2, 'init() adds a vertex to the init graph');
ok($dag->_init_graph->has_vertex($ops[0]), 'init() adds node');
cmp_ok($dag->_init_graph->get_vertex_count($ops[0]), '==', 1, 'init() initial count 1');
$dag->init($ops[0]);
cmp_ok($dag->_init_graph->get_vertex_count($ops[0]), '==', 1, 'init() count still 1');

$dag->init($ops[1]);
$dag->init($ops[2], true);
cmp_ok($dag->_init_graph->vertices, '==', 4,
    'right number of vertices in the init graph before running');

@results=();
$dag->run;      # Fills in @results

# Check the results.  Ops 1 and 2 are added as peers after the initial
# first node, so they can run in any order.  Op 3 is added as the first node
# ($dag->init(..., true)), so will always come before the other two.
ok( eq_deeply(\@results, [3,1,2]) ||
    eq_deeply(\@results, [3,2,1]),
    'Init operations ran in the expected order' );

# Make a cycle in the init graph
$dag->_init_graph->add_edge($ops[$_], $ops[2]) foreach (0, 1);
like( exception { $dag->run }, qr/Initializations contain a cycle/,
    'Detects cycles in init graph');

# goal_class
{
    package MYGoal;
    use parent 'Data::Hopen::G::Goal';
}
{
    package BADGoal;
    # Does not do Data::Hopen::G::Goal!
}

ok("MYGoal"->DOES('Data::Hopen::G::Goal'), "MYGoal does the required role");
$dag = Data::Hopen::G::DAG->new(name=>'foo', goal_class => 'MYGoal');
my $g1 = $dag->goal('all');
isa_ok($g1, 'MYGoal');
is($g1->name, 'all', 'Goal name OK');

ok(!("BADGoal"->DOES('Data::Hopen::G::Goal')), "BADGoal does not do the required role");
like(exception { Data::Hopen::G::DAG->new(name=>'foo', goal_class => 'BADGoal') },
    qr/must implement .+::Goal/, 'goal_class DOES enforcement works');

# Extra tests for coverage

# Anon dag
$dag = Data::Hopen::G::DAG->new();
isa_ok($dag, 'Data::Hopen::G::DAG');
like($dag->name, qr/DAG.*\d/, 'Anon dag gets an autogenerated name');

# Invalid invocations
like exception { Data::Hopen::G::DAG::goal(); }, qr/Need an instance/,
    'goal called directly throws';
like exception { Data::Hopen::G::DAG->goal(); }, qr/Need a goal name/,
    'goal called without name throws';
like exception { Data::Hopen::G::DAG::connect(); }, qr/Need an instance/,
    'connect called directly throws';
like exception { Data::Hopen::G::DAG::add(); }, qr/Missing/,
    'add called directly throws';
like exception { Data::Hopen::G::DAG->add(); }, qr/Missing/,
    'add called without node throws';
like exception { Data::Hopen::G::DAG::init(); }, qr/Need an instance/,
    'init called directly throws';
like exception { Data::Hopen::G::DAG->init(); }, qr/Need an op/,
    'init called without op throws';
like exception { Data::Hopen::G::DAG::empty(); }, qr/Need an instance/,
    'empty called directly throws';
like exception { Data::Hopen::G::DAG::BUILD(); }, qr/Need an instance/,
    'BUILD called directly throws';

done_testing();
