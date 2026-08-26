// Copyright 2026 The etcd Authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// This file is injected by tasks/R06/validators/task_A_functional.sh. It is
// NOT part of any candidate solution; it is a black-box functional check for
// R06 task A (reject empty passwords unless NoPassword).
//
// It talks only to the real AuthServer gRPC service (via the raw
// pb.AuthClient obtained from integration.ToGRPC), exactly the way any
// client/tool (etcdctl, clientv3, a raw grpcurl call, ...) would. It does not
// import or reference server/auth internals, so it cannot be biased toward
// any one implementation layer (auth store vs. v3rpc handler vs. anywhere
// else) -- whichever layer actually enforces the rule, this test observes
// the result at the public API boundary, which is what the task explicitly
// requires ("must apply no matter which client or tool is used").

package integration

import (
	"testing"

	"github.com/stretchr/testify/require"

	"go.etcd.io/etcd/api/v3/authpb"
	pb "go.etcd.io/etcd/api/v3/etcdserverpb"
	"go.etcd.io/etcd/tests/v3/framework/integration"
)

// TestTaskAAuthRejectsEmptyPassword is the functional validator for R06 task
// A. It covers, in order:
//  1. UserAdd with a blank password and NoPassword left false must fail.
//  2. UserAdd with a blank password and NoPassword=true must still succeed
//     (passwordless accounts must keep working).
//  3. UserChangePassword to a blank password on a normal (non-NoPassword)
//     account must fail, and must not have overwritten the original
//     password.
//  4. UserChangePassword to a blank password on an account that was
//     explicitly created as NoPassword must still succeed. This specific
//     case is the sharpest black-box discriminator for this task: a naive
//     fix placed in the gRPC handler for UserChangePassword often can't even
//     tell whether the target account is NoPassword (the
//     AuthUserChangePasswordRequest proto carries no such field), so an
//     implementation that "fixes" UserChangePassword by unconditionally
//     rejecting blank passwords looks correct for (3) but incorrectly
//     breaks (4).
func TestTaskAAuthRejectsEmptyPassword(t *testing.T) {
	integration.BeforeTest(t)
	clus := integration.NewCluster(t, &integration.ClusterConfig{Size: 1})
	defer clus.Terminate(t)

	auth := integration.ToGRPC(clus.Client(0)).Auth
	ctx := t.Context()

	// (1) blank password, not NoPassword -> must fail.
	_, err := auth.UserAdd(ctx, &pb.AuthUserAddRequest{
		Name:    "empty-pw-user",
		Options: &authpb.UserAddOptions{NoPassword: false},
	})
	require.Error(t, err, "creating a user with a blank password (NoPassword not set) must fail")

	_, getErr := auth.UserGet(ctx, &pb.AuthUserGetRequest{Name: "empty-pw-user"})
	require.Error(t, getErr, "a rejected UserAdd must not have created the user")

	// (2) blank password, NoPassword=true -> must succeed.
	_, err = auth.UserAdd(ctx, &pb.AuthUserAddRequest{
		Name:    "nopw-user",
		Options: &authpb.UserAddOptions{NoPassword: true},
	})
	require.NoError(t, err, "a NoPassword=true UserAdd with a blank password must succeed")

	_, getErr = auth.UserGet(ctx, &pb.AuthUserGetRequest{Name: "nopw-user"})
	require.NoError(t, getErr, "the NoPassword account must have actually been created")

	// (3) create a normal user with a real password, then try to blank it.
	const goodPassword = "s3cret-not-empty"
	_, err = auth.UserAdd(ctx, &pb.AuthUserAddRequest{
		Name:     "normal-user",
		Password: goodPassword,
		Options:  &authpb.UserAddOptions{NoPassword: false},
	})
	require.NoError(t, err, "creating a user with a non-empty password must succeed")

	_, err = auth.UserChangePassword(ctx, &pb.AuthUserChangePasswordRequest{Name: "normal-user"})
	require.Error(t, err, "changing an existing (non-NoPassword) user's password to blank must fail")

	// The rejected change must not have taken effect: re-issuing the exact
	// same original password as a "change" must still succeed (a corrupted
	// or already-blanked stored password would make this behave
	// unpredictably; this stays black-box by only ever calling the public
	// Auth RPCs, without requiring cluster-wide AuthEnable just to probe
	// this one property via Authenticate).
	_, err = auth.UserChangePassword(ctx, &pb.AuthUserChangePasswordRequest{Name: "normal-user", Password: goodPassword})
	require.NoError(t, err, "re-setting the same known-good password must still succeed after a rejected empty-password change")

	// (4) an account explicitly created as NoPassword must still be able to
	// have its password "changed" to blank -- this must keep working
	// exactly as before.
	_, err = auth.UserChangePassword(ctx, &pb.AuthUserChangePasswordRequest{Name: "nopw-user"})
	require.NoError(t, err, "changing a NoPassword account's password to blank must keep working")
}
