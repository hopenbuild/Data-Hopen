#!perl
# t/021-dag-single-goal.t: basic tests of Build::Hopen::G::DAG with one goal
use rlib 'lib';
use HopenTest;
use Build::Hopen qw(:default setE);

use Build::Hopen::Environment;
#use Build::Hopen::G::DAG;
#use Build::Hopen::G::PassthroughOp;

$Build::Hopen::VERBOSE = true;

sub run {
    # Create a new environment that will last for the duration of run().
    # See Build::Hopen::setE() for why we can't use `local`.
    my $saver = setE(Build::Hopen::Environment->new);
    my $dag = hnew DAG => 'dag';

    # Add a goal
    my $goal = $dag->goal('all');
    is($goal->name, 'all', 'DAG::goal() sets goal name');
    ok($dag->_graph->has_edge($goal, $dag->_final), 'DAG::goal() adds goal->final edge');

    # Add an op
    my $op = hnew PassthroughOp => 'op1';
    isa_ok($op,'Build::Hopen::G::PassthroughOp');
    $dag->connect($op, $goal);
    ok($dag->_graph->has_edge($op, $goal), 'DAG::connect(.,.) adds edge');

    # Run it
    my $dag_out = $dag->run({foo=>42});

    is_deeply($dag_out, {all => { foo=>42 } }, "DAG passes everything through, tagged with the goal's name");
}

run();

done_testing();